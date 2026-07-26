import AppKit
import Combine
import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dashboard View Model

@MainActor
class DashboardViewModel: ObservableObject {
  // Observe the shared TasksStore
  private let tasksStore = TasksStore.shared

  @Published var scoreResponse: ScoreResponse?
  @Published var goals: [Goal] = []
  @Published var isLoading = false
  @Published var error: String?

  private var cancellables = Set<AnyCancellable>()
  private var lastGoalRefreshTime: Date = .distantPast

  // Computed properties that delegate to TasksStore
  var overdueTasks: [TaskActionItem] { tasksStore.overdueTasks }
  var todaysTasks: [TaskActionItem] { tasksStore.todaysTasks }
  var recentTasks: [TaskActionItem] { tasksStore.tasksWithoutDueDate }

  init() {
    // Forward TasksStore changes to trigger view updates
    tasksStore.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    // Load goals from local SQLite for instant display
    loadGoalsFromLocal()

    // Refresh goals when one is auto-created
    NotificationCenter.default.publisher(for: .goalAutoCreated)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { [weak self] in
          await self?.loadGoals()
        }
      }
      .store(in: &cancellables)
  }

  func loadDashboardData() async {
    isLoading = true
    error = nil

    // Load all data in parallel
    async let scoreTask: Void = loadScores()
    async let tasksTask: Void = tasksStore.refreshDashboardTasksFromServer()
    async let goalsTask: Void = loadGoals()

    let _ = await (scoreTask, tasksTask, goalsTask)

    isLoading = false
  }

  func loadCachedDashboardData() async {
    await loadGoalsFromLocalSnapshot()
  }

  func resetSessionState() {
    scoreResponse = nil
    goals = []
    isLoading = false
    error = nil
    lastGoalRefreshTime = .distantPast
  }

  private func loadScores() async {
    do {
      scoreResponse = try await APIClient.shared.getScores()
    } catch {
      logError("Failed to load scores", error: error)
    }
  }

  private func loadGoals() async {
    // 1. Show local data first (already loaded in init)
    // 2. Fetch from API
    do {
      let apiGoals = try await APIClient.shared.getGoals()
      // 3. Sync to SQLite
      try await GoalStorage.shared.syncServerGoals(apiGoals)
      // 4. Reload from SQLite (source of truth)
      goals = try await GoalStorage.shared.getLocalGoals()
      lastGoalRefreshTime = Date()
    } catch {
      logError("Failed to load goals", error: error)
    }
  }

  /// Refresh goals with 30-second debounce (for app lifecycle events)
  func refreshGoals() {
    let now = Date()
    guard now.timeIntervalSince(lastGoalRefreshTime) > 30 else { return }
    Task {
      await loadGoals()
    }
  }

  // MARK: - Local Goals Storage

  private func loadGoalsFromLocal() {
    Task {
      await loadGoalsFromLocalSnapshot()
    }
  }

  private func loadGoalsFromLocalSnapshot() async {
    do {
      goals = try await GoalStorage.shared.getLocalGoals()
    } catch {
      logError("Failed to load goals from local storage", error: error)
    }
  }

  func toggleTaskCompletion(_ task: TaskActionItem) async {
    // Delegate to shared store - it handles the update
    await tasksStore.toggleTask(task)
    // Reload scores after task completion change
    await loadScores()
  }

  func createGoal(title: String, goalType: GoalType, targetValue: Double, unit: String?) async {
    do {
      let goal = try await APIClient.shared.createGoal(
        title: title,
        goalType: goalType,
        targetValue: targetValue,
        unit: unit,
        source: "user"
      )
      _ = try? await GoalStorage.shared.syncServerGoal(goal)
      goals = try await GoalStorage.shared.getLocalGoals()
    } catch {
      logError("Failed to create goal", error: error)
    }
  }

  func updateGoalProgress(_ goal: Goal, currentValue: Double) async {
    log("Goals: Updating '\(goal.title)' progress to \(currentValue)")

    // Optimistically update local SQLite
    if let index = goals.firstIndex(where: { $0.id == goal.id }) {
      goals[index].currentValue = currentValue
    }
    try? await GoalStorage.shared.updateProgress(backendId: goal.id, currentValue: currentValue)

    do {
      let updated = try await APIClient.shared.updateGoalProgress(
        goalId: goal.id,
        currentValue: currentValue
      )

      // Sync API response to SQLite
      _ = try? await GoalStorage.shared.syncServerGoal(updated)

      // Check if the backend auto-completed this goal
      if updated.completedAt != nil {
        log("Goals: '\(goal.title)' COMPLETED! Triggering celebration.")
        goals = try await GoalStorage.shared.getLocalGoals()
        NotificationCenter.default.post(name: .goalCompleted, object: updated)
        return
      }

      goals = try await GoalStorage.shared.getLocalGoals()
      log("Goals: Updated '\(goal.title)' progress confirmed by API")
    } catch {
      logError("Failed to update goal progress", error: error)
    }
  }

  func updateGoal(_ goal: Goal, title: String, currentValue: Double, targetValue: Double) async {
    log("Goals: Updating goal '\(goal.title)' -> title='\(title)', current=\(currentValue), target=\(targetValue)")

    do {
      let updated = try await APIClient.shared.updateGoal(
        goalId: goal.id,
        title: title,
        currentValue: currentValue,
        targetValue: targetValue
      )

      _ = try? await GoalStorage.shared.syncServerGoal(updated)
      goals = try await GoalStorage.shared.getLocalGoals()
      log("Goals: Updated goal '\(updated.title)' confirmed by API")
    } catch {
      logError("Failed to update goal", error: error)
      goals = (try? await GoalStorage.shared.getLocalGoals()) ?? goals
    }
  }

  func deleteGoal(_ goal: Goal) async {
    do {
      // Soft-delete locally first for instant UI update
      try? await GoalStorage.shared.softDelete(backendId: goal.id)
      goals = try await GoalStorage.shared.getLocalGoals()
      // Then delete on backend
      try await APIClient.shared.deleteGoal(id: goal.id)
    } catch {
      logError("Failed to delete goal", error: error)
    }
  }
}

// MARK: - Dashboard Page

struct DashboardPage: View {
  @ObservedObject var viewModel: DashboardViewModel
  @ObservedObject var homeStatusStore: HomeStatusStore = HomeStatusStore()
  @ObservedObject var appState: AppState
  @ObservedObject var appProvider: AppProvider
  @ObservedObject var chatProvider: ChatProvider
  @ObservedObject var memoriesViewModel: MemoriesViewModel
  var taskChatCoordinator: TaskChatCoordinator? = nil
  @ObservedObject private var deviceProvider = DeviceProvider.shared
  @ObservedObject private var homeSuggestionsStore = HomeSuggestionsStore.shared
  @ObservedObject private var focusStorage = FocusStorage.shared
  @StateObject private var intelligenceStore = DashboardIntelligenceStore()
  /// Learned insights ("things about you") — surfaced in the home hub's rotating
  /// knows-list alongside tasks and asks, not just on the Insights page.
  @ObservedObject private var insightStorage = InsightStorage.shared
  @State private var dismissedKnowsTaskIDs: Set<String> = []
  @State private var homeAskFocusPolicy = HomeAskFocusPolicy()
  @Binding var selectedIndex: Int
  @State private var citedConversation: ServerConversation? = nil
  @State private var selectedCatalogApp: OmiApp?
  @State private var selectedImportConnector: ImportConnector?
  @State private var selectedExportDestination: MemoryExportDestination?
  @State private var isShowingAppsPopup = false
  @State private var appsPopupAcceptsInput = false
  @State private var homeConnectSheetAcceptsInput = false
  @State private var appsPopupInitialSection: AppsCatalogInitialSection = .imports
  @State private var appsPopupPresentationID = UUID()
  @State private var isLoadingCitation = false
  @State private var isCaptureMonitoring = false
  @State private var isTogglingCapture = false
  @State private var isTogglingListening = false
  @State private var showingAllGoals = false
  @State private var showingGoalDetail = false
  @AppStorage("dashboardWidgetsCollapsed") private var widgetsCollapsed = false
  @AppStorage("screenAnalysisEnabled") private var screenAnalysisEnabled = true
  @AppStorage("transcriptionEnabled") private var transcriptionEnabled = true
  @AppStorage("systemAudioCaptureMode") private var systemAudioCaptureModeRaw =
    AssistantSettings.SystemAudioCaptureMode.onlyDuringMeetings.rawValue
  @AppStorage("useLegacyHomeDesign") private var useLegacyHomeDesign = false
  /// Measured height of the floating composer column (suggestions + bar + error
  /// card). The transcript reserves exactly this much at its foot.
  @State private var homeComposerHeight: CGFloat = 0
  @State private var homeMode: HomeStageMode = HomeHistoryPresentationPolicy.openingMode
  @FocusState private var homeAskFieldFocused: Bool
  /// False until `onAppear` has run its stage-opening work, so the mode change
  /// it may perform places the composer rather than travelling it.
  @State private var homeStageDidAppear = false
  /// The composer keeps first responder through a send now that it survives the
  /// travel, and a focused empty field renders no trailing control — which would
  /// retire the Connect chip for good after the first message. Set on send,
  /// cleared the moment there is a draft again.
  @State private var homeComposerHoldsConnect = false

  /// Hub entrance state. `homeHubReveal` drives the staggered entrance and
  /// `homeHubLogoAngle` is the subtle ambient rotation. `chatRevealMonitor` is a
  /// scroll-wheel monitor installed only while the hub shows, so any deliberate
  /// scroll reveals the conversation above it.
  @State private var homeHubReveal = false
  @State private var homeHubLogoAngle: Double = 0
  @StateObject private var chatRevealMonitor = HomeChatRevealMonitor()

  /// Rotation index for the home knows-list; a timer advances it so the hub
  /// cycles through fresh suggestions while you're looking at it.
  @State private var knowsRotation = 0
  private let knowsRotationTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

  private var selectedApp: OmiApp? {
    guard let appId = chatProvider.selectedAppId else { return nil }
    return appProvider.chatApps.first { $0.id == appId }
  }

  private var captureStatus: HomeStatusState {
    CaptureListeningLogic.captureStatus(appState: appState, isCaptureMonitoring: isCaptureMonitoring)
  }

  private var isCaptureLive: Bool {
    CaptureListeningLogic.isCaptureLive(isCaptureMonitoring: isCaptureMonitoring)
  }

  private var listeningCaptureMode: AssistantSettings.SystemAudioCaptureMode {
    CaptureListeningLogic.listeningCaptureMode(raw: systemAudioCaptureModeRaw)
  }

  private var listeningModeTitle: String {
    CaptureListeningLogic.listeningModeTitle(appState: appState, raw: systemAudioCaptureModeRaw)
  }

  private static let homeStageMaxWidth: CGFloat = 1360
  private static let homeStageMinSideInset: CGFloat = 30
  private static let homeStageMaxSideInset: CGFloat = 96
  private static let homeAskBarMinWidth: CGFloat = 560
  private static let homeAskBarMaxWidth: CGFloat = 980
  private static let homeStagePanelMaxWidth: CGFloat = 1280
  private static let homeChatColumnMaxWidth: CGFloat = 680
  /// Fade band under the top bar, and the one the composer sits on top of.
  private static let homeTranscriptTopFade: CGFloat = 24
  private static let homeTranscriptBottomFade: CGFloat = 28
  private static let homeStageTopPadding: CGFloat = 8
  private static let homeStageBottomPadding: CGFloat = 26
  private static let homeStageAnimation = Animation.spring(response: 0.46, dampingFraction: 0.86)
  private static let appsPopupMaxWidth: CGFloat = 1040
  private static let appsPopupMaxHeight: CGFloat = 600
  private static let appsPopupMinWidth: CGFloat = 360
  private static let appsPopupMinHeight: CGFloat = 360
  private static let appsPopupHorizontalMargin: CGFloat = 48
  private static let appsPopupVerticalMargin: CGFloat = 32
  private static let appsPopupCornerRadius: CGFloat = 22
  private static let homeConnectSheetHorizontalMargin: CGFloat = 56
  private static let homeConnectSheetVerticalMargin: CGFloat = 44
  private static let homeConnectSheetMinWidth: CGFloat = 360
  private static let homeConnectSheetMinHeight: CGFloat = 360
  private static let homeConnectSheetCornerRadius: CGFloat = 24
  private static let appDetailSheetPreferredSize = CGSize(width: 500, height: 600)
  private static let importConnectorSheetPreferredSize = CGSize(width: 520, height: 500)
  private static let exportDestinationSheetPreferredSize = CGSize(width: 520, height: 560)

  private var homeConnectSheetIsPresented: Bool {
    selectedCatalogApp != nil || selectedImportConnector != nil || selectedExportDestination != nil
  }

  private var isHomeModalPresented: Bool {
    isShowingAppsPopup || homeConnectSheetIsPresented
  }

  private var legacySelectedCatalogApp: Binding<OmiApp?> {
    Binding(
      get: { useLegacyHomeDesign ? selectedCatalogApp : nil },
      set: { selectedCatalogApp = $0 }
    )
  }

  private var legacySelectedImportConnector: Binding<ImportConnector?> {
    Binding(
      get: { useLegacyHomeDesign ? selectedImportConnector : nil },
      set: { selectedImportConnector = $0 }
    )
  }

  private var legacySelectedExportDestination: Binding<MemoryExportDestination?> {
    Binding(
      get: { useLegacyHomeDesign ? selectedExportDestination : nil },
      set: { selectedExportDestination = $0 }
    )
  }

  private var hasOmiDeviceHistory: Bool {
    deviceProvider.connectedDevice != nil || deviceProvider.pairedDevice != nil
      || homeStatusStore.accountHasOmiDeviceConversations
  }

  /// Real persisted import-connector state (UserDefaults-backed via ImportConnectorStatusStore).
  private func isImportConnectorConnected(_ connectorID: String) -> Bool {
    guard let connector = ImportConnector.all.first(where: { $0.id == connectorID }) else { return false }
    return homeStatusStore.connectorStatusStore.snapshot(for: connector).isConnected
  }

  private func isMCPDestinationConnected(_ destination: MemoryExportDestination) -> Bool {
    switch destination {
    case .claude, .claudeCode:
      return [.claude, .claudeCode].contains { homeStatusStore.memoryExportStatuses[$0]?.hasConnection == true }
    case .chatgpt, .codex:
      return [.chatgpt, .codex].contains { homeStatusStore.memoryExportStatuses[$0]?.hasConnection == true }
    default:
      return homeStatusStore.memoryExportStatuses[destination]?.hasConnection == true
    }
  }

  var body: some View {
    applyChatNavigation(to: applyHomeLifecycle(to: applyHomeSheets(to: homeSurface)))
  }

  /// Opening chat from the notch / Ask-Omi shortcut (posts `.navigateToChat`)
  /// lands in the live chat surface — which shares the notch's transcript —
  /// rather than the resting hero. Kept in its own modifier so the main
  /// lifecycle chain stays type-checkable.
  private func applyChatNavigation<Content: View>(to content: Content) -> some View {
    content
      .onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
        openHomeChat(focusInput: true)
      }
  }

  private var homeSurface: some View {
    Group {
      if useLegacyHomeDesign {
        legacyHome
      } else {
        redesignedHome
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(useLegacyHomeDesign ? Color.clear : HomePalette.paper)
  }

  private func applyHomeSheets<Content: View>(to content: Content) -> some View {
    content
      .sheet(item: $citedConversation) { conversation in
        ConversationDetailView(
          conversation: conversation,
          onBack: {
            citedConversation = nil
          }
        )
        .frame(minWidth: 500, minHeight: 500)
      }
      .sheet(isPresented: $showingAllGoals) {
        AllGoalsSheet(
          store: intelligenceStore,
          onOpenGoal: { goalID in await openGoal(goalID) },
          onDismiss: { showingAllGoals = false }
        )
      }
      .sheet(isPresented: $showingGoalDetail) {
        if let detail = intelligenceStore.selectedGoalDetail {
          CanonicalGoalDetailSheet(
            detail: detail,
            error: intelligenceStore.error,
            onResumeThread: { workstreamID in
              _ = await resumeThread(workstreamID: workstreamID, taskID: nil)
            },
            onStartWork: { await startWorkFromSelectedGoal() },
            onDismiss: {
              showingGoalDetail = false
              intelligenceStore.clearGoalDetail()
            }
          )
        } else {
          ProgressView().frame(width: 300, height: 180)
        }
      }
      .dismissableSheet(item: legacySelectedCatalogApp) { app in
        // Width only: the sheet sizes itself to its content, and a fixed 650
        // around a 600 preferred height just paints a dead band.
        AppDetailSheet(app: app, appProvider: appProvider, onDismiss: { selectedCatalogApp = nil })
          .frame(width: 500)
          .onAppear {
            AnalyticsManager.shared.appDetailViewed(appId: app.id, appName: app.name)
          }
      }
      .dismissableSheet(item: legacySelectedImportConnector) { connector in
        ImportConnectorSheet(
          connector: connector,
          appState: appState,
          statusStore: homeStatusStore.connectorStatusStore,
          onDismiss: {
            selectedImportConnector = nil
          }
        )
        .frame(width: 520, height: 620)
      }
      .dismissableSheet(item: legacySelectedExportDestination) { destination in
        ConnectDestinationSheet(
          destination: destination,
          statuses: $homeStatusStore.memoryExportStatuses,
          onDismiss: {
            selectedExportDestination = nil
          }
        )
        .frame(width: 520, height: 620)
      }
      .overlay {
        if isLoadingCitation {
          ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: OmiSpacing.md) {
              ProgressView()
              Text("Loading source...")
                .scaledFont(size: OmiType.body)
                .foregroundColor(.white)
            }
            .padding(OmiSpacing.xl)
            .background(OmiColors.backgroundSecondary)
            .cornerRadius(OmiChrome.smallControlRadius)
          }
        }
      }
  }

  // Split in two (`applyHomeLifecycle` → `applyHomeStageObservers`) so each
  // modifier chain stays within the type-checker's budget.
  private func applyHomeLifecycle<Content: View>(to content: Content) -> some View {
    applyHomeStageObservers(to: applyHomeLifecycleCore(to: content))
  }

  private func applyHomeLifecycleCore<Content: View>(to content: Content) -> some View {
    content
      .onAppear {
        if PostOnboardingPromptSuggestions.shouldShowPopup && !postOnboardingSuggestions.isEmpty {
          NotificationCenter.default.post(name: .showTryAskingPopup, object: nil)
        }
        syncCaptureState()
        startHomeHubEntrance()
        // Post-onboarding, the resting hub is shown by default — open the chat
        // surface so the personalized opener (set on onboarding completion) is
        // actually visible instead of hidden behind the hub.
        if chatProvider.onboardingOpener != nil { openHomeChat(focusInput: false) }
        consumePendingMainChatOpenRequest()
        homeStageDidAppear = true
        reportHomeAutomationMode()
        intelligenceStore.setRecommendationActionHandler { recommendation in
          await openRecommendation(recommendation)
        }
        intelligenceStore.registerAutomationActions()
        Task { await intelligenceStore.load() }
        Task {
          if let recommendationID = ContextualTaskNavigationRouter.shared.consume() {
            _ = await intelligenceStore.openRecommendation(id: recommendationID)
          }
        }
        Task { await homeStatusStore.refreshIfNeeded() }
        Task { await homeSuggestionsStore.refreshIfNeeded() }
      }
      .onDisappear {
        intelligenceStore.setRecommendationActionHandler(nil)
        // Belt-and-braces with the hub's own onDisappear: an app-global event
        // monitor that outlives the page would fire on every scroll anywhere.
        chatRevealMonitor.stop()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        viewModel.refreshGoals()
        Task { await intelligenceStore.load() }
        appState.checkAllPermissions()
        syncCaptureState()
        Task { await homeStatusStore.refreshIfNeeded() }
        Task { await homeSuggestionsStore.refreshIfNeeded() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .assistantMonitoringStateDidChange)) { _ in
        syncCaptureState()
      }
      .onReceive(NotificationCenter.default.publisher(for: .whatMattersNowContextDidRefresh)) { notification in
        guard let projection = notification.object as? OmiAPI.WhatMattersNowProjection else { return }
        intelligenceStore.applyContextProjection(projection)
      }
      .onReceive(NotificationCenter.default.publisher(for: .openWhatMattersNowRecommendation)) { notification in
        guard
          let recommendationID = notification.userInfo?[
            TaskContextualResurfacingService.recommendationIDUserInfoKey
          ] as? String
        else { return }
        guard ContextualTaskNavigationRouter.shared.consume(requestedID: recommendationID) != nil else { return }
        Task { _ = await intelligenceStore.openRecommendation(id: recommendationID) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .screenCapturePermissionLost)) { _ in
        syncCaptureState()
      }
      .onReceive(NotificationCenter.default.publisher(for: .screenCaptureKitBroken)) { _ in
        syncCaptureState()
      }
  }

  private func applyHomeStageObservers<Content: View>(to content: Content) -> some View {
    content
      // "Continue in Omi" while the dashboard is already mounted; the
      // not-yet-mounted case is covered by the consume in onAppear.
      .onReceive(NotificationCenter.default.publisher(for: .openMainChatRequested)) { _ in
        consumePendingMainChatOpenRequest()
      }
      // The hub keeps its composer on focus. Reaching the transcript is a
      // deliberate act — scroll up, or send — so merely clicking into the bar
      // to type does not leave the hub.
      // Automation-bridge entry points (home_open_chat / home_connect_toggle /
      // home_close_panel / home_ask) — they call the exact functions the
      // on-screen controls call.
      .onReceive(NotificationCenter.default.publisher(for: .homeStageOpenChat)) { _ in
        guard !useLegacyHomeDesign else { return }
        openHomeChat()
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageToggleConnect)) { _ in
        guard !useLegacyHomeDesign else { return }
        toggleHomeConnectPanel()
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageClose)) { _ in
        guard !useLegacyHomeDesign else { return }
        collapseHomeStagePanel()
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageAsk)) { note in
        guard !useLegacyHomeDesign,
          let query = note.userInfo?["query"] as? String
        else { return }
        askHomeSuggestion(query)
      }
      // A draft of your own ends the post-send exemption: the trailing slot goes
      // back to Send, and clearing the field afterwards is an ordinary focused
      // empty field again.
      .onChange(of: chatProvider.draftText) { _, draft in
        if !draft.isEmpty { homeComposerHoldsConnect = false }
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageAttach)) { note in
        guard !useLegacyHomeDesign,
          let path = note.userInfo?["path"] as? String
        else { return }
        // Same wiring the ask bar's paperclip/drag-drop runs after the
        // OS hands back file URLs.
        if let attachment = ChatAttachment.from(url: URL(fileURLWithPath: path)) {
          chatProvider.addAttachments([attachment])
        }
      }
  }

  private var legacyHome: some View {
    VStack(spacing: 0) {
      dashboardWidgets

      ChatMessagesView(
        messages: chatProvider.messages,
        isSending: chatProvider.isSending,
        hasMoreMessages: chatProvider.hasMoreMessages,
        isLoadingMoreMessages: chatProvider.isLoadingMoreMessages,
        isLoadingInitial: chatProvider.isLoading && !chatProvider.isClearing,
        app: selectedApp,
        onLoadMore: { await chatProvider.loadMoreMessages() },
        onRate: { messageId, rating in
          Task { await chatProvider.rateMessage(messageId, rating: rating) }
        },
        onCitationTap: { citation in
          handleCitationTap(citation)
        },
        sessionsLoadError: chatProvider.sessionsLoadError.map {
          UserFacingErrorPresentation.message(from: $0, while: .chatSessions)
        },
        onRetry: { Task { await chatProvider.retryLoad() } },
        localSendToken: chatProvider.localSendToken,
        onOpenAgent: { agentID, completion in
          FloatingControlBarManager.shared.openAgentChatFromTimeline(agentID: agentID, completion: completion)
        },
        onOpenAgentRef: { ref, completion in
          FloatingControlBarManager.shared.openAgentChatFromTimeline(ref: ref, completion: completion)
        },
        welcomeContent: { dashboardChatWelcome }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .mask(
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.92),
            .init(color: .clear, location: 1.0),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )

      dashboardChatErrorCard
        .padding(.horizontal, OmiSpacing.section)

      ChatInputView(
        onSend: { text in
          AnalyticsManager.shared.chatMessageSent(
            messageLength: text.count,
            hasSelectedAppContext: selectedApp != nil,
            source: "dashboard_chat"
          )
          Task { await chatProvider.sendMainDraft(text) }
        },
        onStop: {
          chatProvider.stopAgent(owner: .mainChat)
        },
        isSending: chatProvider.isSending,
        isStopping: chatProvider.isStopping,
        placeholder: "Ask omi anything",
        mode: $chatProvider.chatMode,
        inputText: $chatProvider.draftText,
        attachments: $chatProvider.pendingAttachments,
        onAttachmentsAdded: { urls in
          let toAdd = urls.compactMap { ChatAttachment.from(url: $0) }
          chatProvider.addAttachments(toAdd)
        },
        onAttachmentRemoved: { id in
          chatProvider.removePendingAttachment(id: id)
        }
      )
      .padding(.horizontal, OmiSpacing.section)
      .padding(.top, OmiSpacing.md)
      .padding(.bottom, OmiSpacing.xl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
  }

  // MARK: - Redesigned Home

  private var redesignedHome: some View {
    GeometryReader { proxy in
      let panelHeight = min(max(proxy.size.height - 132, CGFloat(440)), CGFloat(640))
      let panelTop = max(CGFloat(82), (proxy.size.height - panelHeight) / 2)
      let panelWidth = homeStageContentWidth(for: proxy.size.width)

      ZStack(alignment: .topTrailing) {
        HomeCanvasBackground()

        // Clicking anywhere outside the chat / connect panel collapses
        // back to the resting surface (panels and the ask bar consume their
        // own clicks above this catcher). When chat history exists, chat IS
        // the resting Home surface, so no catcher is mounted over it — and
        // the hub is never an overlay, so no catcher is ever mounted over
        // the hub either (a stray click must not throw the user into chat).
        if HomeStageMode.collapseCatcherActive(mode: homeMode, resting: homeRestingMode) {
          Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
              collapseHomeStagePanel()
            }
        }

        homeStage(stageWidth: proxy.size.width, stageHeight: proxy.size.height)
          .frame(width: proxy.size.width, height: proxy.size.height)
          // The popup/sheet overlays are modal: while one is up, the
          // stage underneath must not be reachable by VoiceOver /
          // Full Keyboard Access.
          .accessibilityHidden(isHomeModalPresented)

        // Capture/Listening now live in the shell's constant top bar (see
        // DesktopTopBar), so the home no longer renders its own header copy.

        appsPopupOverlay(
          contentWidth: proxy.size.width,
          panelWidth: panelWidth,
          panelHeight: panelHeight,
          panelTop: panelTop
        )

        homeConnectSheetOverlay(
          contentWidth: proxy.size.width,
          panelWidth: panelWidth,
          panelHeight: panelHeight,
          panelTop: panelTop
        )

        // Esc collapses the connect tray (and, with no chat history, the
        // inline chat) back to the resting surface — but only while no modal
        // overlay owns the key. Chat with history is Home itself and cannot
        // be escaped; the hub is likewise never escaped *into* a panel.
        if HomeStageMode.collapseCatcherActive(mode: homeMode, resting: homeRestingMode)
          && !isHomeModalPresented
        {
          OverlayModalEscapeCatcher {
            collapseHomeStagePanel()
          }
        }
      }
      .omiAnimation(.easeOut(duration: 0.2), value: isShowingAppsPopup)
      .omiAnimation(.easeOut(duration: 0.2), value: homeConnectSheetIsPresented)
    }
  }

  /// One stage for all three modes: the mode surface underneath and a single
  /// composer column over it. `setHomeMode` is the only owner of the stage
  /// curve — a `.animation(value: homeMode)` here would animate the launch
  /// change too, and that is exactly the one that must not move.
  private func homeStage(stageWidth: CGFloat, stageHeight: CGFloat) -> some View {
    let askBarWidth = homeAskBarWidth(for: stageWidth)
    // Keep the knows-list column tight so short rows (e.g. "Call Rabia") don't
    // strand their trailing icon across a wide gap; long one-liners still fit.
    let knowsWidth = min(CGFloat(520), homeStageContentWidth(for: stageWidth))

    return HomeStageLayout(
      slot: HomeComposerPlacement.slot(for: homeMode),
      headlineGap: OmiSpacing.xxl,
      suggestionsGap: OmiSpacing.xxl,
      modeContent: {
        homeStageModeContent(stageWidth: stageWidth, askBarWidth: askBarWidth)
      },
      headline: {
        homeHubHeadline
          .transition(.homeHubStage)
      },
      goals: {
        homeHubGoalsColumn(width: askBarWidth)
          .transition(.homeHubFade)
      },
      composer: {
        homeComposerColumn(askBarWidth: askBarWidth)
      },
      suggestions: {
        homeKnowsList(width: knowsWidth)
          .transition(.homeSuggestionsFade)
          .homeHubReveal(homeHubReveal, delay: 0.18)
      }
    )
    .padding(.top, homeMode.topPadding(hub: Self.homeStageTopPadding))
    .padding(.bottom, Self.homeStageBottomPadding)
  }

  /// The surface the mode owns outright. These genuinely are different views,
  /// so they keep their own entrance transitions.
  @ViewBuilder
  private func homeStageModeContent(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View {
    switch homeMode {
    case .chat:
      homeChatPanel(width: askBarWidth)
        .transition(.homeChatRise)
    case .connect:
      // The tray hugs its content and cannot scroll, so unlike the transcript
      // it has no way to move its last rows out from under the floating
      // composer. It gets the reserved height as real padding.
      homeConnectPanel(stageWidth: stageWidth)
        .padding(.bottom, homeComposerHeight)
        .transition(.homeDropFromTop)
    case .hub:
      EmptyView()
    }
  }

  /// Hub-only surfaces that ride directly above the composer. Deliberately
  /// outside the measured column: the transcript reserves room for what floats
  /// over it, and neither of these is ever on screen while it does.
  private func homeHubGoalsColumn(width: CGFloat) -> some View {
    VStack(spacing: 0) {
      dashboardIntelligenceError
        .frame(width: width)
        .padding(.bottom, intelligenceStore.error == nil ? 0 : OmiSpacing.sm)

      FocusedGoalsSection(
        store: intelligenceStore,
        onOpenGoal: { goalID in await openGoal(goalID) },
        onShowAll: { showingAllGoals = true }
      )
      .frame(width: width)
      .padding(.bottom, hasFocusedGoalsSurface ? OmiSpacing.md : 0)
    }
  }

  /// The composer and everything that floats with it. `homeComposerHeight`
  /// means exactly this column's height — that is the contract the transcript's
  /// bottom inset and cover mask are written against, so nothing that only ever
  /// shows on the hub may be measured here.
  private func homeComposerColumn(askBarWidth: CGFloat) -> some View {
    VStack(spacing: 0) {
      // Above the ask bar while the chat is empty — but not for a just-onboarded
      // user, whose empty chat shows the personalized opener's own starters.
      if showsRollingSuggestions {
        homeRollingSuggestions
          .frame(width: askBarWidth)
          .padding(.bottom, OmiSpacing.sm)
          .transition(.homeSuggestionsFade)
      }

      homeAskBar
        .frame(width: askBarWidth)

      dashboardChatErrorCard
        .frame(width: askBarWidth)
        .padding(.top, OmiSpacing.sm)
    }
    // The transcript reserves exactly this much room at its foot, so the last
    // row can always be scrolled clear of the bar however tall the bar gets.
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: { height in
      // Sub-pixel noise must not re-enter layout through the inset it feeds.
      if abs(homeComposerHeight - height) > 0.5 { homeComposerHeight = height }
    }
    // The suggestion block is three rows tall. Dropping it on the first send
    // with no transaction takes that height out from under the transcript in a
    // single frame, which lands on top of the row-insert spring and reads as
    // the whole stage flinching. One curve owns the handover.
    //
    // The measured height itself is deliberately never animated. It feeds the
    // transcript's bottom inset and its cover mask, so interpolating it makes
    // every frame of the curve a full transcript re-measure.
    .omiAnimation(SBMotion.message, value: showsRollingSuggestions)
  }

  /// Retired: `homeStage` merged both arms into one `HomeStageLayout` so the
  /// composer keeps a single identity across hub↔chat. Nothing constructs this
  /// any more; it stays in-tree so its removal can be its own reviewable change.
  ///
  /// Hub layout: the greeting headline and knows-list rows centered on the
  /// stage over the memory constellation, with the goals/error surfaces and
  /// the ask bar docked as one column at the bottom.
  private func homeHubStage(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View {
    // Keep the knows-list column tight so short rows (e.g. "Call Rabia") don't
    // strand their trailing icon across a wide gap; long one-liners still fit.
    let columnWidth = min(CGFloat(520), homeStageContentWidth(for: stageWidth))

    return VStack(spacing: 0) {
      Spacer(minLength: 0)

      homeHubHeadline
        .transition(.homeHubFade)

      homeKnowsList(width: columnWidth)
        .padding(.top, OmiSpacing.xxl)
        .transition(.homeSuggestionsFade)
        .homeHubReveal(homeHubReveal, delay: 0.18)

      Spacer(minLength: 0)

      VStack(spacing: 0) {
        dashboardIntelligenceError
          .frame(width: askBarWidth)
          .padding(.bottom, intelligenceStore.error == nil ? 0 : OmiSpacing.sm)

        FocusedGoalsSection(
          store: intelligenceStore,
          onOpenGoal: { goalID in await openGoal(goalID) },
          onShowAll: { showingAllGoals = true }
        )
        .frame(width: askBarWidth)
        .padding(.bottom, hasFocusedGoalsSurface ? OmiSpacing.md : 0)

        homeAskBar
          .frame(width: askBarWidth)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var hasFocusedGoalsSurface: Bool {
    !intelligenceStore.focusedGoals.isEmpty || intelligenceStore.accountGeneration != nil
  }

  /// Retired: `homeStage` merged both arms into one `HomeStageLayout`, which is
  /// where the transcript/composer overlap and the measured reserve now live.
  /// Nothing constructs this any more; it stays in-tree so its removal can be
  /// its own reviewable change.
  ///
  /// Panel layout (chat / connect): the surface fills the height with the ask
  /// bar anchored beneath it. Mounting the bar in each arm gave the two arms
  /// distinct structural identities, so hub→chat destroyed one composer and
  /// created another — the reason focus, hover and drop state all reset there.
  /// The transcript fills the stage and the composer floats over its foot.
  ///
  /// Stacking them instead left a fixed gap between the two that nothing used,
  /// and made the transcript's height a function of the composer's — so growing
  /// the input for a second line resized the surface above it. Overlapping gives
  /// that height back to the transcript and lets text pass behind the bar, which
  /// is what every chat client does and what the fade band exists to sell.
  private func homePanelStage(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View {
    ZStack(alignment: .bottom) {
      Group {
        switch homeMode {
        case .chat:
          homeChatPanel(width: askBarWidth)
            .transition(.homeChatRise)
        case .connect:
          // The tray hugs its content and cannot scroll, so unlike the
          // transcript it has no way to move its last rows out from under the
          // floating composer. It gets the reserved height as real padding.
          homeConnectPanel(stageWidth: stageWidth)
            .padding(.bottom, homeComposerHeight)
            .transition(.homeDropFromTop)
        case .hub:
          EmptyView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      VStack(spacing: 0) {
        // Above the ask bar while the chat is empty — but not for a just-onboarded
        // user, whose empty chat shows the personalized opener's own starters.
        if showsRollingSuggestions {
          homeRollingSuggestions
            .frame(width: askBarWidth)
            .padding(.bottom, OmiSpacing.sm)
            .transition(.homeSuggestionsFade)
        }

        homeAskBar
          .frame(width: askBarWidth)

        dashboardChatErrorCard
          .frame(width: askBarWidth)
          .padding(.top, OmiSpacing.sm)
      }
      // The transcript reserves exactly this much room at its foot, so the last
      // row can always be scrolled clear of the bar however tall the bar gets.
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: { height in
        // Sub-pixel noise must not re-enter layout through the inset it feeds.
        if abs(homeComposerHeight - height) > 0.5 { homeComposerHeight = height }
      }
    }
    // The suggestion block is three rows tall. Dropping it on the first send
    // with no transaction takes that height out from under the transcript in a
    // single frame, which lands on top of the row-insert spring and reads as
    // the whole stage flinching. One curve owns the handover.
    .omiAnimation(SBMotion.message, value: showsRollingSuggestions)
    .omiAnimation(SBMotion.standard, value: homeComposerHeight)
  }

  /// Whether the rolling prompt suggestions have a reason to be on screen.
  /// Chat only: the hub and the connect tray have their own rows under the
  /// composer, and the pills would stack on top of them.
  private var showsRollingSuggestions: Bool {
    homeMode == .chat && chatProvider.messages.isEmpty && chatProvider.onboardingOpener == nil
  }

  /// Kicks off the hub's staggered entrance and its subtle ambient rotation.
  /// Both gate off cleanly under Reduce Motion.
  private func startHomeHubEntrance() {
    homeHubReveal = true
    guard !OmiMotion.reduceMotion else { return }
    withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
      homeHubLogoAngle = 360
    }
  }

  /// A small, auto-rotating set of prompt suggestions shown above the ask bar on
  /// an empty home chat — replaces the old greeting hero + knows-list cards.
  private var homeRollingSuggestions: some View {
    VStack(spacing: OmiSpacing.xs) {
      ForEach(Array(homeKnowsRows.prefix(3))) { row in
        Button {
          openKnowsRow(row)
        } label: {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: rollingSuggestionIcon(row.kind))
              .scaledFont(size: OmiType.caption)
              .foregroundStyle(HomePalette.muted)
            Text(row.text)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundStyle(HomePalette.secondary)
              .lineLimit(1)
            Spacer(minLength: 8)
          }
          .padding(.horizontal, OmiSpacing.md)
          .frame(height: 34)
          .frame(maxWidth: .infinity)
          .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(HomePalette.tile.opacity(0.5)))
          .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .stroke(HomePalette.hairline.opacity(0.55), lineWidth: 1)
          )
          .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .transition(.opacity)
      }
    }
    .omiAnimation(.easeInOut(duration: 0.45), value: knowsRotation)
    .onReceive(knowsRotationTimer) { _ in
      guard homeMode == .chat, chatProvider.messages.isEmpty, !chatProvider.isSending, homeKnowsCanRotate
      else { return }
      knowsRotation += 1
    }
  }

  private func rollingSuggestionIcon(_ kind: HomeKnowsRowKind) -> String {
    switch kind {
    case .task: return "circle"
    case .insight: return "lightbulb"
    case .focus: return "eye"
    case .question: return "bubble.left"
    }
  }

  // MARK: Hub centerpiece

  /// Home's one empty state. The mark turns slowly at rest so omi reads as
  /// present rather than idle, and the cluster settles in sequence on open.
  ///
  /// A deliberate scroll here reveals the conversation living above it, which
  /// is the only way past the hub other than sending.
  private var homeHubHeadline: some View {
    VStack(spacing: OmiSpacing.sm) {
      SBLogo(size: 40, spinning: chatProvider.isSending)
        .rotationEffect(.degrees(chatProvider.isSending ? 0 : homeHubLogoAngle))
        .padding(.bottom, OmiSpacing.lg)
        .homeHubReveal(homeHubReveal, delay: 0)

      Text(homeHubGreeting)
        .scaledFont(size: OmiType.hero, weight: .bold)
        .foregroundStyle(HomePalette.ink)
        .multilineTextAlignment(.center)
        .homeHubReveal(homeHubReveal, delay: 0.06)

      Text(homeDailyBrief)
        .scaledFont(size: OmiType.subheading)
        .foregroundStyle(HomePalette.muted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .homeHubReveal(homeHubReveal, delay: 0.12)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .onAppear {
      chatRevealMonitor.start(
        shouldReveal: { homeMode == .hub && !isHomeModalPresented && !chatProvider.messages.isEmpty },
        onReveal: { openHomeChat(focusInput: false) }
      )
    }
    .onDisappear { chatRevealMonitor.stop() }
  }

  private var homeHubGreeting: String {
    let name = AuthService.shared.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "I'm ready." : "Hey \(name). I'm ready."
  }

  // MARK: Knows list

  /// Insight rows for the hub: the task-intelligence recommendations plus the
  /// learned insights ("things about you") from the Insights store, so the hub
  /// surfaces insights, not only tasks and asks.
  private var homeKnowsInsightCandidates: [HomeKnowsInsightCandidate] {
    let recommendations = intelligenceStore.recommendations.map {
      HomeKnowsInsightCandidate(id: $0.id, text: $0.headline)
    }
    let learned = insightStorage.insightHistory
      .filter { !$0.isDismissed }
      .prefix(12)
      .map { HomeKnowsInsightCandidate(id: $0.id, text: $0.insight.insight) }
    return recommendations + Array(learned)
  }

  private var homeKnowsRows: [HomeKnowsRow] {
    HomeKnowsListComposer.compose(
      tasks: homeKnowsTaskCandidates,
      insights: homeKnowsInsightCandidates,
      tip: homeActionTip,
      questions: homeSuggestedQuestions,
      dismissedTaskIDs: dismissedKnowsTaskIDs,
      rotation: knowsRotation
    )
  }

  /// True when there are more candidates than the hub shows, so rotating cycles
  /// to genuinely different rows instead of the same set.
  private var homeKnowsCanRotate: Bool {
    HomeKnowsListComposer.canRotate(
      taskCount: homeKnowsTaskCandidates.filter { !dismissedKnowsTaskIDs.contains($0.id) }.count,
      insightCount: homeKnowsInsightCandidates.count,
      questionCount: homeSuggestedQuestions.count
    )
  }

  /// A composed, high-agency nudge for the tip slot when there's no server
  /// insight — one thing you can hand Omi with a tap (it prefills the chat).
  private var homeActionTip: String? {
    if focusStorage.currentStatus == .distracted {
      return "Help me get back on track"
    }
    let openCount =
      homeKnowsTaskCandidates
      .filter { !dismissedKnowsTaskIDs.contains($0.id) }
      .count
    if openCount >= 5 {
      return "Sort my open tasks — which 3 actually matter today?"
    }
    return "Recap what I got done today"
  }

  /// A short, conversational read on the day — what you've been doing and how
  /// much is waiting — shown under the greeting. It absorbs the focus status so
  /// the action rows below stay purely actionable.
  private var homeDailyBrief: String {
    let openCount =
      homeKnowsTaskCandidates
      .filter { !dismissedKnowsTaskIDs.contains($0.id) }
      .count
    let tail: String
    switch openCount {
    case 0: tail = "nothing's waiting on you."
    case 1: tail = "one thing needs you."
    default: tail = "\(openCount) things need you."
    }

    var lead: String?
    if let status = focusStorage.currentStatus {
      let rawApp = focusStorage.currentApp ?? focusStorage.detectedAppName
      let appName = rawApp?.trimmingCharacters(in: .whitespacesAndNewlines)
      let namedApp: String? = {
        guard let appName, !appName.isEmpty,
          !appName.lowercased().contains("unknown")
        else { return nil }
        return appName
      }()
      if status == .focused, let namedApp {
        lead = "Deep in \(namedApp) today"
      } else if status == .focused {
        lead = "Heads-down today"
      } else if status == .distracted {
        lead = "A scattered stretch just now"
      }
    }

    if let lead {
      return "\(lead) — \(tail)"
    }
    return tail.prefix(1).uppercased() + tail.dropFirst()
  }

  private var homeKnowsTaskCandidates: [HomeKnowsTaskCandidate] {
    (viewModel.overdueTasks + viewModel.todaysTasks + viewModel.recentTasks)
      .filter { !$0.completed && $0.deleted != true }
      .map { HomeKnowsTaskCandidate(id: $0.id, text: $0.description) }
  }

  private func homeKnowsList(width: CGFloat) -> some View {
    VStack(spacing: OmiSpacing.sm) {
      ForEach(homeKnowsRows) { row in
        HomeKnowsRowView(
          row: row,
          onOpen: { openKnowsRow(row) },
          onDismiss: knowsDismissHandler(for: row),
          onLater: knowsLaterHandler(for: row)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .frame(width: width)
    .omiAnimation(.easeInOut(duration: 0.45), value: knowsRotation)
    .onReceive(knowsRotationTimer) { _ in
      // Only rotate on the resting hub, when idle, and when there's genuinely
      // more to show — so the set feels alive without churning under you.
      guard homeMode == .hub, !chatProvider.isSending, homeKnowsCanRotate else { return }
      knowsRotation += 1
    }
    .accessibilityIdentifier("home-knows-list")
  }

  private func openKnowsRow(_ row: HomeKnowsRow) {
    switch row.kind {
    case .task(let id):
      if let task = (viewModel.overdueTasks + viewModel.todaysTasks + viewModel.recentTasks)
        .first(where: { $0.id == id })
      {
        TaskNavigationRequestStore.shared.request(task: task)
      }
      navigate(to: .tasks)
    case .insight(let id):
      guard let recommendation = intelligenceStore.recommendations.first(where: { $0.id == id })
      else { return }
      Task {
        if await openRecommendation(recommendation) {
          await intelligenceStore.recordPrimaryAction(recommendation)
        }
      }
    case .focus:
      navigate(to: .focus)
    case .question:
      // Prefill the ask bar so you can glance it over and edit before sending,
      // rather than firing the suggestion blindly.
      chatProvider.draftText = row.text
      homeAskFieldFocused = true
    }
  }

  private func knowsDismissHandler(for row: HomeKnowsRow) -> ((OmiAPI.TaskIntelligenceFeedbackReason?) -> Void)? {
    switch row.kind {
    case .task(let id):
      return { _ in dismissedKnowsTaskIDs.insert(id) }
    case .insight(let id):
      return { reason in
        guard let recommendation = intelligenceStore.recommendations.first(where: { $0.id == id })
        else { return }
        Task { await intelligenceStore.dismiss(recommendation, reason: reason) }
      }
    case .focus, .question:
      return nil
    }
  }

  private func knowsLaterHandler(for row: HomeKnowsRow) -> (() -> Void)? {
    guard case .insight(let id) = row.kind else { return nil }
    return {
      guard let recommendation = intelligenceStore.recommendations.first(where: { $0.id == id })
      else { return }
      Task { await intelligenceStore.later(recommendation) }
    }
  }

  // MARK: Inline chat panel

  private func homeChatPanel(width: CGFloat) -> some View {
    VStack(spacing: 0) {
      ChatMessagesView(
        messages: chatProvider.messages,
        isSending: chatProvider.isSending,
        hasMoreMessages: chatProvider.hasMoreMessages,
        isLoadingMoreMessages: chatProvider.isLoadingMoreMessages,
        isLoadingInitial: chatProvider.isLoading && !chatProvider.isClearing,
        app: selectedApp,
        onLoadMore: { await chatProvider.loadMoreMessages() },
        onRate: { messageId, rating in
          Task { await chatProvider.rateMessage(messageId, rating: rating) }
        },
        onCitationTap: { citation in
          handleCitationTap(citation)
        },
        sessionsLoadError: chatProvider.sessionsLoadError.map {
          UserFacingErrorPresentation.message(from: $0, while: .chatSessions)
        },
        onRetry: { Task { await chatProvider.retryLoad() } },
        localSendToken: chatProvider.localSendToken,
        onCancelTurn: { chatProvider.stopAgent(owner: .mainChat) },
        onOpenAgent: { agentID, completion in
          FloatingControlBarManager.shared.openAgentChatFromTimeline(agentID: agentID, completion: completion)
        },
        onOpenAgentRef: { ref, completion in
          FloatingControlBarManager.shared.openAgentChatFromTimeline(ref: ref, completion: completion)
        },
        horizontalContentPadding: 0,
        verticalContentPadding: OmiSpacing.sm,
        // The scroller is on the shell edge now, well clear of the column, so
        // right-aligned pills no longer need to be held off it.
        trailingContentPadding: 0,
        contentColumnWidth: width,
        bottomContentInset: homeComposerHeight + Self.homeTranscriptBottomFade,
        transcriptFadeHeight: Self.homeTranscriptTopFade,
        composerCoverHeight: homeComposerHeight,
        welcomeContent: { dashboardChatWelcome }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Chat is the Home surface itself — no card chrome, it sits directly on the
    // ambient canvas. The scroll view spans the stage so the macOS overlay
    // scroller rides the shell's edge; the readable column is capped on the rows
    // instead, and still matches the ask bar's width so message edges line up
    // with the bar's.
    .frame(maxWidth: .infinity)
  }

  // MARK: Connect tray

  private func homeConnectPanel(stageWidth: CGFloat) -> some View {
    // Sources feed omi; omi's memory flows out to the AI destinations —
    // the chevron between the two cards reads that direction. The tray
    // hugs its content: no scroll filler below the columns.
    HStack(alignment: .center, spacing: OmiSpacing.md) {
      homeConnectColumnCard {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          sourceColumnHeader
          sourceConstellation
        }
      }

      Image(systemName: "chevron.right")
        .scaledFont(size: OmiType.body, weight: .bold)
        .foregroundStyle(HomePalette.secondary)
        .frame(width: 30, height: 30)
        .background(Circle().fill(HomePalette.tile))
        .overlay(Circle().stroke(HomePalette.hairline, lineWidth: 1))
        .accessibilityHidden(true)

      homeConnectColumnCard {
        destinationStack
      }
    }
    .padding(OmiSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(HomePalette.panel.opacity(0.94))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(HomePalette.hairline.opacity(0.9), lineWidth: 1)
    )
    .overlay(alignment: .topTrailing) {
      HomeIconActionButton(title: "Close connect", systemImage: "xmark") {
        collapseHomeStagePanel()
      }
      .padding(OmiSpacing.md)
    }
    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
    .frame(width: homeStagePanelWidth(for: stageWidth))
  }

  private func homeConnectColumnCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(OmiSpacing.lg)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .fill(Color.white.opacity(0.025))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .stroke(HomePalette.hairline.opacity(0.55), lineWidth: 1)
      )
  }

  // MARK: Ask bar + suggestions

  @ViewBuilder
  private var dashboardChatErrorCard: some View {
    if let cardState = chatProvider.currentError {
      ChatErrorCard(
        state: cardState,
        onRecover: {
          Task { await chatProvider.recoverFromError() }
        },
        onDismiss: {
          chatProvider.dismissCurrentError()
        }
      )
    }
  }

  private var homeAskBar: some View {
    HomeAskBar(
      text: $chatProvider.draftText,
      isSending: chatProvider.isSending,
      isStopping: chatProvider.isStopping,
      isConnectActive: homeMode == .connect,
      focus: $homeAskFieldFocused,
      attachments: $chatProvider.pendingAttachments,
      onAttachmentsAdded: { urls in
        let toAdd = urls.compactMap { ChatAttachment.from(url: $0) }
        chatProvider.addAttachments(toAdd)
      },
      onAttachmentRemoved: { id in
        chatProvider.removePendingAttachment(id: id)
      },
      keepsConnectWhileEmpty: homeComposerHoldsConnect,
      onSend: sendFromHomeAskBar,
      onStop: { chatProvider.stopAgent(owner: .mainChat) },
      onConnect: toggleHomeConnectPanel,
      // Tapping the bar begins a fresh chat and focuses it to type, staying on
      // the hero; only sending enters the chat surface (see sendFromHomeAskBar).
      onActivate: { focusHomeAskBar() }
    )
  }

  private var homeSuggestedQuestions: [String] {
    HomeSuggestionComposer.compose(
      personalized: homeSuggestionsStore.personalizedQuestions,
      onboarding: PostOnboardingPromptSuggestions.suggestions()
    )
  }

  private func homeStageSideInset(for stageWidth: CGFloat) -> CGFloat {
    min(Self.homeStageMaxSideInset, max(Self.homeStageMinSideInset, stageWidth * 0.06))
  }

  private func homeStageContentWidth(for stageWidth: CGFloat) -> CGFloat {
    let sideInset = homeStageSideInset(for: stageWidth)
    return min(Self.homeStageMaxWidth, max(CGFloat(0), stageWidth - (sideInset * 2)))
  }

  private func homeStagePanelWidth(for stageWidth: CGFloat) -> CGFloat {
    min(Self.homeStagePanelMaxWidth, homeStageContentWidth(for: stageWidth))
  }

  private func homeAskBarWidth(for stageWidth: CGFloat) -> CGFloat {
    let contentWidth = homeStageContentWidth(for: stageWidth)
    if homeMode != .hub {
      // Chat mode: bar and message column share one readable width, edges
      // aligned (bubbles start/end on the bar's verticals).
      return min(Self.homeChatColumnMaxWidth, contentWidth)
    }

    let availableWidth = min(Self.homeAskBarMaxWidth, contentWidth)
    let text = chatProvider.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return min(availableWidth, Self.homeAskBarMinWidth)
    }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: OmiType.subheading)
    ]
    let measuredTextWidth = (text as NSString).size(withAttributes: attributes).width
    // Leading inset + paperclip + gaps + the trailing action slot. Sized from
    // the slot's own constant rather than a number tuned against the Connect
    // chip, which is not the mode the bar is in once the field has focus and
    // there is a draft to measure.
    let chromeWidth = OmiSpacing.lg + 24 + OmiSpacing.sm * 2 + HomeAskBarMetrics.accessoryReserve
    return min(availableWidth, max(Self.homeAskBarMinWidth, measuredTextWidth + chromeWidth))
  }

  // MARK: Stage actions

  private func reportHomeAutomationMode() {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    let modeLabel = useLegacyHomeDesign ? nil : homeMode.automationLabel
    _ = DesktopAutomationStateStore.shared.updateLiveFields { snapshot in
      snapshot.homeMode = modeLabel
      snapshot.updatedAt = ISO8601DateFormatter().string(from: Date())
    }
  }

  /// Floating-bar "Continue in Omi": land directly on the chat panel instead
  /// of whatever surface Home was resting on.
  private func consumePendingMainChatOpenRequest() {
    guard MainChatNavigationRequestStore.shared.consume() else { return }
    guard !useLegacyHomeDesign else { return }
    openHomeChat()
  }
  private func openHomeChat(focusInput: Bool = true) {
    // Never an early return: the hotkey has to reach the focus request even when
    // chat is already the visible stage.
    if homeMode != .chat {
      setHomeMode(.chat)
    }
    if focusInput {
      focusHomeAskFieldAfterStageTransition()
    }
    reportHomeAutomationMode()
  }

  /// The single owner of the stage curve. Every mode change routes through here
  /// so one rule decides whether the composer travels between its slots or is
  /// simply placed in the new one.
  private func setHomeMode(_ target: HomeStageMode) {
    let previous = homeMode
    guard previous != target else { return }
    guard
      HomeComposerPlacement.shouldAnimate(
        from: previous,
        to: target,
        isInitialAppearance: !homeStageDidAppear
      )
    else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { homeMode = target }
      return
    }
    OmiMotion.withGated(Self.homeStageAnimation) {
      homeMode = target
    }
  }

  private func focusHomeAskFieldAfterStageTransition() {
    let token = homeAskFocusPolicy.currentToken()
    Task { @MainActor in
      await Task.yield()
      // A deferred focus is stale once anything connects / collapses / closes
      // (each bumps the policy's generation), and must never land on a non-chat
      // stage — both would route back through the focus observer into chat.
      guard homeAskFocusPolicy.isCurrent(token), homeMode == .chat else { return }
      homeAskFieldFocused = true
    }
  }

  /// The surface Home rests on when no panel is explicitly open: the chat
  /// timeline once any history exists, otherwise the greeting hub.
  /// Home opens directly in the continuous chat (no greeting hero). Rolling
  /// suggestions sit above the ask bar while the chat is empty.
  private var homeRestingMode: HomeStageMode {
    HomeHistoryPresentationPolicy.restingMode
  }

  /// User-facing collapse (click outside, Esc, connect ×) and the automation
  /// bridge's `home_close_panel`: returns to the resting surface. There is a
  /// single close path now — the bridge no longer force-jumps to the hub.
  private func collapseHomeStagePanel() {
    homeAskFieldFocused = false
    homeAskFocusPolicy.invalidate()
    homeComposerHoldsConnect = false
    setHomeMode(homeRestingMode)
    reportHomeAutomationMode()
  }

  private func toggleHomeConnectPanel() {
    homeAskFocusPolicy.invalidate()
    let target: HomeStageMode = homeMode == .connect ? homeRestingMode : .connect
    if target == .connect {
      homeAskFieldFocused = false
    }
    setHomeMode(target)
    reportHomeAutomationMode()
  }

  /// Omi is one continuous chat — tapping the ask bar just focuses it to type,
  /// continuing the single thread (no new sessions, no history).
  private func focusHomeAskBar() {
    homeAskFieldFocused = true
  }

  private func sendFromHomeAskBar() {
    let draft = chatProvider.draftText
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    // Text is required — ChatProvider.sendMessage no-ops on empty text, so
    // an attachment-only "send" would silently drop the turn.
    guard !text.isEmpty else { return }
    openHomeChat(focusInput: false)
    homeComposerHoldsConnect = true
    AnalyticsManager.shared.chatMessageSent(
      messageLength: text.count,
      hasSelectedAppContext: selectedApp != nil,
      source: "home_ask_bar"
    )
    if chatProvider.isSending {
      return
    } else {
      Task { await chatProvider.sendMainDraft(draft) }
    }
  }

  private func askHomeSuggestion(_ suggestion: String) {
    openHomeChat(focusInput: false)
    AnalyticsManager.shared.chatMessageSent(
      messageLength: suggestion.count,
      hasSelectedAppContext: selectedApp != nil,
      source: "home_suggested_question"
    )
    Task { await chatProvider.sendMessage(suggestion) }
  }

  @ViewBuilder
  private func appsPopupOverlay(
    contentWidth: CGFloat,
    panelWidth: CGFloat,
    panelHeight: CGFloat,
    panelTop: CGFloat
  ) -> some View {
    ZStack {
      if isShowingAppsPopup {
        Color.black.opacity(0.16)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture {
            dismissAppsPopup()
          }
          .transition(.opacity)
          .zIndex(2)

        let popupSize = appsPopupSize(panelWidth: panelWidth, panelHeight: panelHeight)

        AppsPage(
          appProvider: appProvider,
          appState: appState,
          connectorStatusStore: homeStatusStore.connectorStatusStore,
          initialSection: appsPopupInitialSection,
          onDismiss: {
            dismissAppsPopup()
          },
          onSelectApp: { app in
            openAppFromAppsPopup(app)
          },
          onSelectConnector: { connector in
            openImportConnectorFromAppsPopup(connector)
          },
          onSelectDestination: { destination in
            openExportDestinationFromAppsPopup(destination)
          }
        )
        .id(appsPopupPresentationID)
        .frame(width: popupSize.width, height: popupSize.height)
        .background(OmiColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Self.appsPopupCornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Self.appsPopupCornerRadius, style: .continuous)
            .stroke(HomePalette.hairline.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 26, y: 14)
        .position(x: contentWidth / 2, y: panelTop + panelHeight / 2)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .accessibilityAddTraits(.isModal)
        .zIndex(3)

        // Only the topmost modal owns Esc; the connect sheet takes over
        // while it is presented (including the brief crossfade overlap).
        if appsPopupAcceptsInput && !homeConnectSheetIsPresented {
          OverlayModalEscapeCatcher {
            dismissAppsPopup()
          }
          .zIndex(3)
        }
      }
    }
    .allowsHitTesting(appsPopupAcceptsInput && !homeConnectSheetIsPresented)
    .zIndex(2)
  }

  @ViewBuilder
  private func homeConnectSheetOverlay(
    contentWidth: CGFloat,
    panelWidth: CGFloat,
    panelHeight: CGFloat,
    panelTop: CGFloat
  ) -> some View {
    ZStack {
      if homeConnectSheetIsPresented {
        Color.black.opacity(0.22)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture {
            dismissHomeConnectSheet()
          }
          .transition(.opacity)
          .zIndex(4)

        let sheetSize = homeConnectSheetSize(panelWidth: panelWidth, panelHeight: panelHeight)

        homeConnectSheetContent()
          .frame(width: sheetSize.width, height: sheetSize.height)
          .background(OmiColors.backgroundPrimary)
          .clipShape(RoundedRectangle(cornerRadius: Self.homeConnectSheetCornerRadius, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Self.homeConnectSheetCornerRadius, style: .continuous)
              .stroke(HomePalette.hairline.opacity(0.92), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.42), radius: 30, y: 16)
          .position(x: contentWidth / 2, y: panelTop + panelHeight / 2)
          .transition(.scale(scale: 0.96).combined(with: .opacity))
          .accessibilityAddTraits(.isModal)
          .zIndex(5)

        if homeConnectSheetAcceptsInput {
          OverlayModalEscapeCatcher {
            dismissHomeConnectSheet()
          }
          .zIndex(5)
        }
      }
    }
    .allowsHitTesting(homeConnectSheetAcceptsInput)
    .zIndex(4)
  }

  private func homeConnectSheetSize(panelWidth: CGFloat, panelHeight: CGFloat) -> CGSize {
    let preferred = homeConnectSheetPreferredSize
    return CGSize(
      width: min(
        preferred.width,
        max(Self.homeConnectSheetMinWidth, panelWidth - (Self.homeConnectSheetHorizontalMargin * 2))
      ),
      height: min(
        preferred.height,
        max(Self.homeConnectSheetMinHeight, panelHeight - (Self.homeConnectSheetVerticalMargin * 2))
      )
    )
  }

  private var homeConnectSheetPreferredSize: CGSize {
    if selectedCatalogApp != nil {
      return Self.appDetailSheetPreferredSize
    }
    if selectedImportConnector != nil {
      return Self.importConnectorSheetPreferredSize
    }
    return Self.exportDestinationSheetPreferredSize
  }

  @ViewBuilder
  private func homeConnectSheetContent() -> some View {
    if let app = selectedCatalogApp {
      AppDetailSheet(app: app, appProvider: appProvider, onDismiss: { dismissHomeConnectSheet() })
        .onAppear {
          AnalyticsManager.shared.appDetailViewed(appId: app.id, appName: app.name)
        }
    } else if let connector = selectedImportConnector {
      ImportConnectorSheet(
        connector: connector,
        appState: appState,
        statusStore: homeStatusStore.connectorStatusStore,
        onDismiss: {
          dismissHomeConnectSheet()
        }
      )
    } else if let destination = selectedExportDestination {
      ConnectDestinationSheet(
        destination: destination,
        statuses: $homeStatusStore.memoryExportStatuses,
        onDismiss: {
          dismissHomeConnectSheet()
        }
      )
    }
  }

  private func appsPopupSize(panelWidth: CGFloat, panelHeight: CGFloat) -> CGSize {
    CGSize(
      width: min(
        Self.appsPopupMaxWidth,
        max(Self.appsPopupMinWidth, panelWidth - (Self.appsPopupHorizontalMargin * 2))
      ),
      height: min(
        Self.appsPopupMaxHeight,
        max(Self.appsPopupMinHeight, panelHeight - (Self.appsPopupVerticalMargin * 2))
      )
    )
  }

  /// The retired Home-specific copy of the Capture/Listening chips. Nothing
  /// renders it since the shell rework gave the top bar one persistent copy on
  /// every page, `CaptureListeningControls`; it stays in-tree so its removal can
  /// be its own reviewable change. Because it is unreachable it does not get the
  /// truthful chip state the live copy has — reconnecting it would mean adopting
  /// that first.
  private var homeHeader: some View {
    let transcriptionUnavailable = appState.transcriptionServiceError != nil

    return HStack {
      Spacer()
      HStack(spacing: OmiSpacing.sm) {
        HomeStatusButton(
          title: "Capture",
          systemImage: "viewfinder",
          status: captureStatus,
          isToggling: isTogglingCapture,
          action: toggleCapture
        )
        // Rewind isn't a top-level tab; it opens from a right-click on Capture.
        .contextMenu {
          Button {
            navigate(to: .rewind)
          } label: {
            Label("Open Rewind", systemImage: "clock.arrow.circlepath")
          }
        }

        HomeListeningStatusButton(
          title: transcriptionUnavailable ? "Transcription unavailable" : "Listening",
          systemImage: transcriptionUnavailable
            ? "exclamationmark.triangle.fill"
            : (appState.isTranscribing ? "waveform.circle.fill" : "mic.circle"),
          status: transcriptionUnavailable ? .blocked : (appState.isTranscribing ? .active : .inactive),
          modeTitle: listeningModeTitle,
          isMeetingsOnly: listeningCaptureMode == .onlyDuringMeetings,
          isToggling: isTogglingListening,
          action: toggleListening,
          modeAction: toggleListeningMode
        )
        // Settings lives in the nav rail (bottom-left) — no duplicate gear here.
      }
    }
    .frame(height: 36)
  }

  private var sourceColumnHeader: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text("Connect data")
        .font(.system(size: 20, weight: .medium, design: .serif))
        .foregroundStyle(HomePalette.ink)

      Text("Sources Omi learns from.")
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundStyle(HomePalette.muted)
        .lineLimit(1)
    }
  }

  private var sourceConstellation: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HomeAIChoiceButton(title: "Gmail", brand: .gmail, isConnected: isImportConnectorConnected("email")) {
        openImportConnector("email")
      }
      HomeAIChoiceButton(title: "Calendar", brand: .calendar, isConnected: isImportConnectorConnected("calendar")) {
        openImportConnector("calendar")
      }
      HomeAIChoiceButton(title: "Files", brand: .localFiles, isConnected: isImportConnectorConnected("local-files")) {
        openImportConnector("local-files")
      }
      HomeAIChoiceButton(title: "Notes", brand: .appleNotes, isConnected: isImportConnectorConnected("apple-notes")) {
        openImportConnector("apple-notes")
      }
      HomeAIChoiceButton(title: "Omi Device", usesOmiMark: true, isConnected: hasOmiDeviceHistory) {
        openOmiDeviceWebsite()
      }
      HomeAIChoiceButton(title: "More", systemImage: "plus") {
        openAppsPopup(initialSection: .imports)
      }
    }
  }

  private var destinationStack: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Use omi memory anywhere")
          .font(.system(size: 20, weight: .medium, design: .serif))
          .foregroundStyle(HomePalette.ink)

        Text("Bring your memories to the apps you use")
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundStyle(HomePalette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

      HomeAIChoiceButton(title: "Ask Omi", usesOmiMark: true) {
        openHomeChat()
      }
      HomeAIChoiceButton(title: "Claude / Claude Code", brand: .claude, isConnected: isMCPDestinationConnected(.claude))
      {
        openExportDestination(.claudeCode)
      }
      HomeAIChoiceButton(title: "ChatGPT / Codex", brand: .chatgpt, isConnected: isMCPDestinationConnected(.chatgpt)) {
        openExportDestination(.chatgpt)
      }
      HomeAIChoiceButton(title: "OpenClaw", brand: .openclaw, isConnected: isMCPDestinationConnected(.openclaw)) {
        openExportDestination(.openclaw)
      }
      HomeAIChoiceButton(title: "Hermes", brand: .hermes, isConnected: isMCPDestinationConnected(.hermes)) {
        openExportDestination(.hermes)
      }
      HomeAIChoiceButton(title: "More", systemImage: "plus") {
        openAppsPopup(initialSection: .exports)
      }
    }
  }

  private func navigate(to item: SidebarNavItem) {
    selectedIndex = item.rawValue
    AnalyticsManager.shared.tabChanged(tabName: item.title)
  }

  private func openAppsPopup(initialSection: AppsCatalogInitialSection) {
    // Filters left behind by earlier catalog visits (a category, a search,
    // "Installed") would otherwise replace the Imports/Exports sections
    // this popup exists to show.
    appProvider.clearFilters()
    appsPopupInitialSection = initialSection
    appsPopupPresentationID = UUID()
    appsPopupAcceptsInput = true
    isShowingAppsPopup = true
  }

  private func dismissAppsPopup() {
    appsPopupAcceptsInput = false
    isShowingAppsPopup = false
  }

  private func openAppFromAppsPopup(_ app: OmiApp) {
    dismissAppsPopup()
    presentCatalogApp(app)
  }

  private func openImportConnectorFromAppsPopup(_ connector: ImportConnector) {
    dismissAppsPopup()
    presentImportConnector(connector)
  }

  private func openExportDestinationFromAppsPopup(_ destination: MemoryExportDestination) {
    dismissAppsPopup()
    presentExportDestination(destination)
  }

  private func openImportConnector(_ connectorID: String) {
    if let connector = ImportConnector.all.first(where: { $0.id == connectorID }) {
      presentImportConnector(connector)
    }
  }

  private func openExportDestination(_ destination: MemoryExportDestination) {
    presentExportDestination(destination)
  }

  private func presentCatalogApp(_ app: OmiApp) {
    homeConnectSheetAcceptsInput = true
    selectedImportConnector = nil
    selectedExportDestination = nil
    selectedCatalogApp = app
  }

  private func presentImportConnector(_ connector: ImportConnector) {
    homeConnectSheetAcceptsInput = true
    selectedCatalogApp = nil
    selectedExportDestination = nil
    selectedImportConnector = connector
  }

  private func presentExportDestination(_ destination: MemoryExportDestination) {
    homeConnectSheetAcceptsInput = true
    selectedCatalogApp = nil
    selectedImportConnector = nil
    selectedExportDestination = destination
  }

  private func dismissHomeConnectSheet() {
    homeConnectSheetAcceptsInput = false
    selectedCatalogApp = nil
    selectedImportConnector = nil
    selectedExportDestination = nil
  }

  private func openOmiDeviceWebsite() {
    if let url = URL(string: "https://www.omi.me") {
      NSWorkspace.shared.open(url)
    }
  }

  private func toggleListening() {
    CaptureListeningLogic.toggleListening(
      appState: appState, transcriptionEnabled: $transcriptionEnabled, isTogglingListening: $isTogglingListening)
  }

  private func toggleListeningMode() {
    CaptureListeningLogic.toggleListeningMode(raw: $systemAudioCaptureModeRaw)
  }

  private func toggleCapture() {
    CaptureListeningLogic.toggleCapture(
      appState: appState, screenAnalysisEnabled: $screenAnalysisEnabled,
      isCaptureMonitoring: $isCaptureMonitoring, isTogglingCapture: $isTogglingCapture)
  }

  private func syncCaptureState() {
    CaptureListeningLogic.syncCaptureState(
      screenAnalysisEnabled: $screenAnalysisEnabled, isCaptureMonitoring: $isCaptureMonitoring)
  }

  /// Welcome message shown when there are no chat messages yet.
  /// Transparent — no card chrome — so it morphs into the dashboard background.
  /// Empty-state of the Home chat: the personalized post-onboarding opener when
  /// one is pending (this is where onboarding lands the user), else the default
  /// "Ask omi anything" welcome.
  /// The transcript's empty slot. The hub owns "Home has nothing to show yet",
  /// so an empty `.chat` is not a state the reader ever sits in — only the
  /// instant between pressing send and the row landing. A second hero there
  /// flashed for a frame and then was replaced, which reads as a glitch.
  ///
  /// The onboarding opener stays: it is a real first-run surface with its own
  /// starters, not a duplicate of the hub.
  @ViewBuilder private var dashboardChatWelcome: some View {
    if let opener = chatProvider.onboardingOpener {
      OnboardingOpenerView(opener: opener, chatProvider: chatProvider)
    }
  }

  /// Handle tapping on a citation card — opens the cited conversation in a sheet.
  private func handleCitationTap(_ citation: Citation) {
    guard citation.sourceType == .conversation else {
      log("Citation tapped: \(citation.title) (memory - no detail view)")
      return
    }

    isLoadingCitation = true

    Task {
      do {
        let conversation = try await APIClient.shared.getConversation(id: citation.id)
        await MainActor.run {
          citedConversation = conversation
          isLoadingCitation = false
        }
      } catch {
        logError("Failed to fetch cited conversation", error: error)
        await MainActor.run {
          isLoadingCitation = false
        }
      }
    }
  }

  private func openRecommendation(_ recommendation: DashboardRecommendation) async -> Bool {
    switch recommendation.destination {
    case .suggested(let candidateID):
      guard let candidate = await intelligenceStore.candidateForNavigation(candidateID: candidateID) else {
        return false
      }
      TaskNavigationRequestStore.shared.request(candidate: candidate)
      selectedIndex = 4
      return true
    case .task(let taskID, let workstreamID):
      if let workstreamID {
        return await resumeThread(workstreamID: workstreamID, taskID: taskID)
      } else {
        guard let task = await intelligenceStore.taskForNavigation(taskID: taskID) else {
          return false
        }
        TaskNavigationRequestStore.shared.request(task: task)
        selectedIndex = 4
        return true
      }
    case .thread(let workstreamID, let taskID):
      return await resumeThread(workstreamID: workstreamID, taskID: taskID)
    case .unavailable:
      intelligenceStore.error = "This review target is no longer available."
      return false
    }
  }

  private func openGoal(_ goalID: String) async {
    await intelligenceStore.loadGoalDetail(goalID: goalID)
    guard intelligenceStore.selectedGoalDetail != nil else { return }
    showingAllGoals = false
    showingGoalDetail = true
  }

  @discardableResult
  private func resumeThread(workstreamID: String, taskID: String?) async -> Bool {
    guard let taskChatCoordinator else {
      intelligenceStore.error = "The task thread is unavailable."
      return false
    }
    if await taskChatCoordinator.openExistingThread(
      workstreamID: workstreamID,
      preferredTaskID: taskID
    ) {
      showingGoalDetail = false
      showingAllGoals = false
      selectedIndex = 4
      return true
    } else {
      intelligenceStore.error = taskChatCoordinator.errorMessage ?? "The task thread could not be opened."
      return false
    }
  }

  private func startWorkFromSelectedGoal() async {
    guard let detail = intelligenceStore.selectedGoalDetail, let taskChatCoordinator else {
      intelligenceStore.error = "The goal thread is unavailable."
      return
    }
    do {
      let receipt = try await taskChatCoordinator.resolveGoalOrigin(
        goalId: detail.goal.goalId,
        occurrenceId: "goal-detail-primary-v1",
        title: detail.goal.title,
        objective: detail.goal.desiredOutcome,
        anchorTaskDescription: "Make progress on \(detail.goal.title)"
      )
      await resumeThread(workstreamID: receipt.workstreamId, taskID: receipt.taskId)
    } catch {
      intelligenceStore.error = "Omi could not start work on this goal."
    }
  }

  // MARK: - Summary counts for collapsed bar

  private var incompleteTaskCount: Int {
    viewModel.overdueTasks.count + viewModel.todaysTasks.count + viewModel.recentTasks.count
  }

  private var activeGoalCount: Int {
    intelligenceStore.accountGeneration == nil
      ? viewModel.goals.count
      : intelligenceStore.currentGoals.count
  }

  // MARK: - Dashboard Widgets (collapsible)

  private var dashboardWidgets: some View {
    VStack(alignment: .leading, spacing: widgetsCollapsed ? 0 : OmiSpacing.xl) {
      if shouldShowSuggestionBanner {
        PromptSuggestionBanner(
          suggestions: postOnboardingSuggestions,
          onOpen: {
            dismissSuggestionBanner()
            NotificationCenter.default.post(name: .showTryAskingPopup, object: nil)
          },
          onAsk: handleSuggestedPrompt,
          onDismiss: dismissSuggestionBanner
        )
      }

      dashboardIntelligenceError

      FocusedGoalsSection(
        store: intelligenceStore,
        onOpenGoal: { goalID in await openGoal(goalID) },
        onShowAll: { showingAllGoals = true }
      )

      if widgetsCollapsed {
        // Collapsed: slim summary bar
        collapsedWidgetBar
      } else {
        // Expanded: full Tasks + Goals cards
        expandedWidgets

        // Collapse button centered below widgets
        collapseButton
      }
    }
    .padding(.horizontal, OmiSpacing.section)
    .padding(.top, widgetsCollapsed ? OmiSpacing.xl : OmiSpacing.section)
    .padding(.bottom, OmiSpacing.sm)
    .omiAnimation(.easeInOut(duration: 0.25), value: widgetsCollapsed)
  }

  @ViewBuilder
  private var dashboardIntelligenceError: some View {
    if let error = intelligenceStore.error, !error.isEmpty {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.warning)
        Text(error)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
        Spacer(minLength: OmiSpacing.sm)
        Button("Retry") {
          Task { await intelligenceStore.load() }
        }
        .buttonStyle(.plain)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textPrimary)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(OmiColors.backgroundSecondary.opacity(0.88))
      )
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .stroke(OmiColors.border.opacity(0.7), lineWidth: 1)
      )
      .accessibilityIdentifier("dashboard-intelligence-error")
    }
  }

  private var collapsedWidgetBar: some View {
    Button(action: { widgetsCollapsed = false }) {
      HStack(spacing: OmiSpacing.lg) {
        // Tasks summary
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "checklist")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
          Text(
            incompleteTaskCount == 0
              ? "No tasks"
              : "\(incompleteTaskCount) task\(incompleteTaskCount == 1 ? "" : "s")"
          )
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundColor(OmiColors.textSecondary)
        }

        // Subtle divider dot
        Circle()
          .fill(OmiColors.textQuaternary)
          .frame(width: 3, height: 3)

        // Goals summary
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "target")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
          Text(
            activeGoalCount == 0
              ? "No goals"
              : "\(activeGoalCount) goal\(activeGoalCount == 1 ? "" : "s")"
          )
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundColor(OmiColors.textSecondary)
        }

        Spacer()

        // Expand chevron
        Image(systemName: "chevron.down")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(OmiColors.textQuaternary)
      }
      .padding(.horizontal, OmiSpacing.lg)
      .padding(.vertical, OmiSpacing.md)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
          .fill(OmiColors.backgroundSecondary.opacity(0.6))
      )
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
          .stroke(OmiColors.border.opacity(0.12), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private var expandedWidgets: some View {
    // fixedSize(vertical:) constrains the Grid to its row's intrinsic
    // height so Tasks/Goals stop competing with ChatMessagesView for
    // vertical space; each cell still fills the row, so the two cards
    // remain visually equal-height (matching the taller intrinsic).
    Grid(horizontalSpacing: OmiSpacing.xl, verticalSpacing: OmiSpacing.xl) {
      GridRow {
        TasksWidget(
          overdueTasks: viewModel.overdueTasks,
          todaysTasks: viewModel.todaysTasks,
          recentTasks: viewModel.recentTasks,
          onToggleCompletion: { task in
            Task {
              await viewModel.toggleTaskCompletion(task)
            }
          }
        )
        .frame(minWidth: 0, maxWidth: .infinity)

        if intelligenceStore.accountGeneration != nil {
          canonicalGoalsWidget
        } else {
          GoalsWidget(
            goals: viewModel.goals,
            onCreateGoal: { title, current, target in
              Task {
                await viewModel.createGoal(
                  title: title,
                  goalType: .numeric,
                  targetValue: target,
                  unit: nil
                )
              }
            },
            onUpdateGoal: { goal, title, current, target in
              Task {
                await viewModel.updateGoal(
                  goal,
                  title: title,
                  currentValue: current,
                  targetValue: target
                )
              }
            },
            onUpdateProgress: { goal, value in
              Task { await viewModel.updateGoalProgress(goal, currentValue: value) }
            },
            onDeleteGoal: { goal in
              Task { await viewModel.deleteGoal(goal) }
            }
          )
          .frame(minWidth: 0, maxWidth: .infinity)
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private var canonicalGoalsWidget: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HStack {
        Text("Goals")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        Button("All goals") { showingAllGoals = true }
          .buttonStyle(.plain)
          .scaledFont(size: OmiType.micro, weight: .medium)
      }
      FocusedGoalsSection(
        store: intelligenceStore,
        onOpenGoal: { goalID in await openGoal(goalID) },
        onShowAll: { showingAllGoals = true }
      )
      if intelligenceStore.focusedGoals.isEmpty {
        Text("Keep a few outcomes in focus.")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(OmiSpacing.lg)
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(OmiColors.backgroundSecondary.opacity(0.65))
    )
  }

  private var collapseButton: some View {
    HStack {
      Spacer()
      Button(action: { widgetsCollapsed = true }) {
        Image(systemName: "chevron.up")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(OmiColors.textQuaternary)
          .frame(width: 48, height: 20)
      }
      .buttonStyle(.plain)
      Spacer()
    }
  }

  private var postOnboardingSuggestions: [String] {
    PostOnboardingPromptSuggestions.suggestions()
  }

  private var shouldShowSuggestionBanner: Bool {
    !postOnboardingSuggestions.isEmpty && !PostOnboardingPromptSuggestions.isDismissed
  }

  private func dismissSuggestionBanner() {
    PostOnboardingPromptSuggestions.shouldShowPopup = false
    PostOnboardingPromptSuggestions.isDismissed = true
  }

  private func handleSuggestedPrompt(_ suggestion: String) {
    PostOnboardingPromptSuggestions.shouldShowPopup = false
    FloatingControlBarManager.shared.openAIInputWithQuery(suggestion)
  }

}

// MARK: - Home Components

enum HomePalette {
  static let paper = Color(red: 0.018, green: 0.019, blue: 0.021)
  static let panel = Color(red: 0.045, green: 0.046, blue: 0.052)
  static let tile = Color(red: 0.078, green: 0.078, blue: 0.088)
  static let tileHover = Color(red: 0.108, green: 0.110, blue: 0.122)
  static let ink = Color(red: 0.97, green: 0.97, blue: 0.975)
  static let secondary = Color(red: 0.72, green: 0.73, blue: 0.75)
  static let muted = Color(red: 0.46, green: 0.47, blue: 0.50)
  static let faint = Color(red: 0.34, green: 0.35, blue: 0.37)
  static let hairline = Color(red: 0.155, green: 0.155, blue: 0.172)
  static let green = Color(red: 0.17, green: 0.78, blue: 0.38)
  // Neutral cool-grey key light (INV-UI-1 brand accent rules).
  static let stageGlow = Color(red: 0.72, green: 0.74, blue: 0.78)
  static let glow = stageGlow
}

/// One knows-list row: leading kind icon, single-line text, and either a
/// dismiss × (task/insight) or an ask ↗ (question) on the trailing edge.
private struct HomeKnowsRowView: View {
  let row: HomeKnowsRow
  let onOpen: () -> Void
  let onDismiss: ((OmiAPI.TaskIntelligenceFeedbackReason?) -> Void)?
  let onLater: (() -> Void)?

  @State private var isHovering = false
  @State private var showDismissReasons = false
  @State private var choseReason = false

  private var leadingIcon: String {
    switch row.kind {
    case .task: return "circle"
    case .insight: return "lightbulb"
    case .focus: return "eye"
    case .question: return "bubble.left"
    }
  }

  var body: some View {
    Button(action: onOpen) {
      HStack(spacing: OmiSpacing.md) {
        Image(systemName: leadingIcon)
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundStyle(isHovering ? HomePalette.secondary : HomePalette.muted)
          .frame(width: 18)

        Text(row.text)
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundStyle(isHovering ? HomePalette.ink : HomePalette.secondary)
          .lineLimit(1)

        Spacer(minLength: 8)

        trailingAccessory
      }
      .padding(.horizontal, OmiSpacing.lg)
      .frame(height: 46)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile.opacity(0.62))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(HomePalette.hairline.opacity(isHovering ? 1 : 0.55), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: 13))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .contextMenu {
      if let onLater {
        Button("Later") { onLater() }
      }
      if onDismiss != nil {
        Button("Dismiss") { handleDismissTap() }
      }
    }
    .accessibilityLabel(row.text)
    .accessibilityIdentifier("home-knows-\(row.id)")
  }

  @ViewBuilder
  private var trailingAccessory: some View {
    if onDismiss != nil {
      Button(action: handleDismissTap) {
        Image(systemName: "xmark")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundStyle(isHovering ? HomePalette.secondary : HomePalette.faint)
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Dismiss")
      .accessibilityLabel("Dismiss")
      .popover(isPresented: $showDismissReasons) {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          Text("Optional reason")
            .scaledFont(size: OmiType.caption, weight: .semibold)
          ForEach(Self.reasonChoices, id: \.label) { choice in
            Button(choice.label) {
              choseReason = true
              onDismiss?(choice.reason)
              showDismissReasons = false
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(OmiSpacing.md)
        .frame(width: 210)
      }
      .onChange(of: showDismissReasons) { wasShowing, isShowing in
        guard wasShowing, !isShowing, !choseReason else { return }
        onDismiss?(nil)
      }
    } else {
      Image(systemName: "arrow.up.right")
        .scaledFont(size: OmiType.micro, weight: .bold)
        .foregroundStyle(isHovering ? HomePalette.ink : HomePalette.faint)
    }
  }

  /// Insight dismissals offer the same optional feedback reasons the old
  /// What-matters-now cards recorded; task rows just hide for the session.
  private func handleDismissTap() {
    if case .insight = row.kind {
      choseReason = false
      showDismissReasons = true
    } else {
      onDismiss?(nil)
    }
  }

  private static let reasonChoices: [(label: String, reason: OmiAPI.TaskIntelligenceFeedbackReason)] = [
    ("Already handled", .already_handled),
    ("Not mine", .not_mine),
    ("Not useful", .not_useful),
  ]
}

private struct HomeCanvasBackground: View {
  var body: some View {
    // A clean, flat neutral-dark canvas — no muddy glow. One very soft
    // top-to-bottom lift keeps the surface from reading dead-flat.
    LinearGradient(
      colors: [
        Color(red: 0.056, green: 0.058, blue: 0.065),
        Color(red: 0.040, green: 0.042, blue: 0.048),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}

private struct HomePrimaryRouteButton: View {
  let title: String
  let brand: ConnectorBrand
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        ConnectorBrandIcon(brand: brand, size: 20, cornerRadius: OmiChrome.badgeRadius)

        Text(title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .lineLimit(1)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(minWidth: 118)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(HomePalette.green.opacity(isHovering ? 0.92 : 1))
      )
      .shadow(color: HomePalette.green.opacity(isHovering ? 0.22 : 0.12), radius: 12, y: 5)
      .contentShape(.rect(cornerRadius: OmiChrome.smallControlRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("Connect \(title)")
  }
}

private struct HomeInlineAction: View {
  let title: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let action: () -> Void

  @State private var isHovering = false

  init(title: String, brand: ConnectorBrand, action: @escaping () -> Void) {
    self.title = title
    self.brand = brand
    self.systemImage = nil
    self.action = action
  }

  init(title: String, systemImage: String, action: @escaping () -> Void) {
    self.title = title
    self.brand = nil
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.xs) {
        icon

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
          .lineLimit(1)

        Image(systemName: "chevron.right")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundStyle(HomePalette.faint)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        Capsule(style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile.opacity(0.72))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(isHovering ? HomePalette.green.opacity(0.3) : HomePalette.hairline.opacity(0.42), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  @ViewBuilder
  private var icon: some View {
    if let brand {
      ConnectorBrandIcon(brand: brand, size: 18, cornerRadius: OmiChrome.badgeRadius)
    } else if let systemImage {
      Image(systemName: systemImage)
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundStyle(HomePalette.secondary)
        .frame(width: 18, height: 18)
    }
  }
}

enum HomeStatusState {
  case active
  case inactive
  case blocked

  var indicator: Color {
    switch self {
    case .active:
      return HomePalette.green
    case .inactive:
      return HomePalette.faint
    case .blocked:
      return Color(red: 1.0, green: 0.24, blue: 0.30)
    }
  }

  var text: String {
    switch self {
    case .active:
      return "On"
    case .inactive:
      return "Off"
    case .blocked:
      return "Blocked"
    }
  }

  var isActive: Bool {
    if case .active = self { return true }
    return false
  }

  var isBlocked: Bool {
    if case .blocked = self { return true }
    return false
  }
}

private struct HomeIconActionButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundStyle(isHovering ? HomePalette.ink : HomePalette.muted)
        .frame(width: 34, height: 34)
        .background(
          Circle()
            .fill(isHovering ? HomePalette.tileHover : HomePalette.panel)
        )
        .overlay(
          Circle()
            .stroke(HomePalette.hairline.opacity(isHovering ? 0.8 : 0.58), lineWidth: 1)
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(title)
    .accessibilityLabel(title)
  }
}

private struct HomeConnectorCard: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand
  let actionTitle: String
  let status: String?
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ConnectorBrandIcon(brand: brand, size: 36, cornerRadius: 9)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(OmiColors.textTertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 10)

        if let status {
          HStack(spacing: OmiSpacing.xxs) {
            Image(systemName: "checkmark")
              .scaledFont(size: OmiType.micro, weight: .bold)
            Text(status)
              .scaledFont(size: OmiType.caption, weight: .semibold)
          }
          .foregroundStyle(OmiColors.success)
          .lineLimit(1)
        } else {
          HStack(spacing: OmiSpacing.xxs) {
            Image(systemName: "plus")
              .scaledFont(size: OmiType.micro, weight: .bold)
            Text(actionTitle)
              .scaledFont(size: OmiType.caption, weight: .semibold)
          }
          .foregroundStyle(OmiColors.success)
          .lineLimit(1)
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(minHeight: 56)
      .background(cardBackground)
      .overlay(cardStroke)
      .contentShape(.rect(cornerRadius: OmiChrome.smallControlRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(status ?? actionTitle)")
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
      .fill(OmiColors.backgroundSecondary.opacity(isHovering ? 0.94 : 0.72))
  }

  private var cardStroke: some View {
    RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
      .stroke(
        isHovering ? OmiColors.success.opacity(0.32) : OmiColors.border.opacity(0.42),
        lineWidth: 1
      )
  }
}

private struct HomeMoreAppsCard: View {
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
            .fill(OmiColors.backgroundPrimary)
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
                .stroke(OmiColors.border.opacity(0.55), lineWidth: 1)
            )

          Image(systemName: "square.grid.2x2.fill")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundStyle(OmiColors.textSecondary)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text("Connect more")
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)

          Text("Browse all apps")
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(OmiColors.textTertiary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(OmiColors.success)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(minHeight: 56)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(OmiColors.backgroundSecondary.opacity(isHovering ? 0.94 : 0.72))
      )
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .stroke(
            isHovering ? OmiColors.success.opacity(0.32) : OmiColors.border.opacity(0.42),
            lineWidth: 1
          )
      )
      .contentShape(.rect(cornerRadius: OmiChrome.smallControlRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

private struct HomeFlowArrow: View {
  var body: some View {
    VStack(spacing: OmiSpacing.xxs) {
      Rectangle()
        .fill(OmiColors.border.opacity(0.75))
        .frame(width: 1, height: 14)

      Image(systemName: "chevron.down")
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundStyle(OmiColors.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }
}

private struct HomeMetricCard: View {
  let title: String
  let value: String
  let subtitle: String
  let systemImage: String
  let accent: Color
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
            .fill(accent.opacity(0.16))
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
            )

          Image(systemName: systemImage)
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundStyle(accent)
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(value)
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)
            .lineLimit(1)

          Text(title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundStyle(OmiColors.textTertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Image(systemName: "arrow.up.right")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(isHovering ? accent : OmiColors.textQuaternary)
      }
      .padding(OmiSpacing.md)
      .frame(minHeight: 64)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
          .fill(OmiColors.backgroundSecondary.opacity(isHovering ? 0.96 : 0.78))
      )
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
          .stroke(isHovering ? accent.opacity(0.34) : OmiColors.border.opacity(0.44), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: OmiChrome.chipRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(value), \(subtitle)")
  }
}

private struct HomeAIButton: View {
  let title: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let action: () -> Void

  @State private var isHovering = false

  init(title: String, brand: ConnectorBrand, action: @escaping () -> Void) {
    self.title = title
    self.brand = brand
    self.systemImage = nil
    self.action = action
  }

  init(title: String, systemImage: String, action: @escaping () -> Void) {
    self.title = title
    self.brand = nil
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        if let brand {
          ConnectorBrandIcon(brand: brand, size: 26, cornerRadius: 7)
        } else if let systemImage {
          ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(OmiColors.backgroundTertiary)
            Image(systemName: systemImage)
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .foregroundStyle(OmiColors.textSecondary)
          }
          .frame(width: 26, height: 26)
        }

        Text(title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(OmiColors.textSecondary)
          .lineLimit(1)

        Image(systemName: "chevron.right")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundStyle(isHovering ? OmiColors.success : OmiColors.textQuaternary)
      }
      .padding(.leading, OmiSpacing.sm)
      .padding(.trailing, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.xs)
      .background(
        Capsule(style: .continuous)
          .fill(OmiColors.backgroundSecondary.opacity(isHovering ? 0.96 : 0.76))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(isHovering ? OmiColors.success.opacity(0.32) : OmiColors.border.opacity(0.42), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(title)
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    DashboardPage(
      viewModel: DashboardViewModel(),
      appState: AppState(),
      appProvider: AppProvider(),
      chatProvider: ChatProvider(),
      memoriesViewModel: MemoriesViewModel(),
      selectedIndex: .constant(0)
    )
    .frame(width: 800, height: 600)
    .background(OmiColors.backgroundPrimary)
  }
#endif
