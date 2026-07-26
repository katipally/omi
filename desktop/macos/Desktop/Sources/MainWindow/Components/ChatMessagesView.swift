import OmiTheme
import SwiftUI

/// A token that callers pass when the local user sends a message.
/// This allows ChatMessagesView to distinguish genuine user sends from
/// messages arriving via polling, sync, or other sources — without
/// inferring solely from messages.count changes.
struct LocalSendToken: Equatable {
  /// Monotonic counter that increments on every local send.
  /// ChatMessagesView tracks the last seen value and reacts to increments.
  let generation: Int
}

/// Pure duplicate-detection for the chat transcript. Extracted so it is unit
/// testable and so the fingerprint can't silently collide distinct messages.
enum ChatMessageDeduplicator {
  /// IDs of long messages that are exact duplicates of an earlier message in
  /// the same list. The fingerprint is sender + the FULL body: an earlier
  /// implementation keyed only on the first 200 characters, so two genuinely
  /// distinct long messages that shared an opening (same preamble, different
  /// answer) collided and the later one was hidden. Only true whole-message
  /// duplicates (sync/poll replay) should collapse.
  static func duplicateIDs(in messages: [ChatMessage]) -> Set<String> {
    var seen: [String: String] = [:]  // sender+full-text fingerprint → first message ID
    var dupes = Set<String>()
    for msg in messages {
      // A live reply passes through every prefix of its final text, so any
      // fingerprint taken mid-stream describes a message that does not exist
      // yet. Only settled rows can be duplicates of one another.
      guard !msg.isStreaming else { continue }
      guard msg.text.count > 200 else { continue }  // only dedup long messages
      let fingerprint = "\(msg.sender)\u{1}\(msg.text)"
      if seen[fingerprint] != nil {
        dupes.insert(msg.id)
      } else {
        seen[fingerprint] = msg.id
      }
    }
    return dupes
  }
}

/// Vertical rhythm for the transcript. A flat gap between every row makes a
/// question and its answer look as unrelated as two separate exchanges, so the
/// gap that opens a turn is wider than the gaps inside one.
enum ChatTurnSpacing {
  static let withinTurn: CGFloat = 12
  static let betweenTurns: CGFloat = 32

  /// Gap above `current`, given the sender of the row before it. A user
  /// message that follows omi opens a new turn; everything else continues the
  /// turn already in progress. The first row of a transcript gets no gap.
  static func leadingGap(previous: ChatSender?, current: ChatSender) -> CGFloat {
    guard let previous else { return 0 }
    return current == .user && previous != .user ? betweenTurns : withinTurn
  }
}

/// Timing for following a streaming reply.
///
/// The follow itself is `ChatLiveEdgeFollower`, which integrates the scroll
/// offset toward the live edge every display frame. These are the surrounding
/// timings: when it runs, and what the *other* scroll paths do.
enum ChatStreamScroll {
  /// Coalescing window for content that is not a paced reveal — a tool card
  /// landing, an attachment strip appearing. Those add their height in one
  /// step, so they get a short commanded move rather than a jump.
  static let throttle: TimeInterval = 0.08
  static let animation: Animation = .easeOut(duration: 0.18)

  /// How long the follow keeps running after the stream ends. The reveal is
  /// paced on its own clock (`ChatRevealModel`), so the transcript is still
  /// growing for a beat after the last token lands; stopping the follow with
  /// the stream would strand that tail below the fold.
  static let settleTail: TimeInterval = 1.5
}

/// The motion a sent message makes on its way into the transcript.
///
/// The composer sits immediately below the transcript, so a user row that
/// starts a row's height lower and settles upward reads as the text leaving the
/// bar it was typed in. It is the same illusion iMessage uses: nothing actually
/// travels from the field, the bubble simply arrives from where the field is.
enum ChatSendMotion {
  static let riseDistance: CGFloat = 52
  static let enteringScale: CGFloat = 0.94
  static let insert: Animation = .spring(response: 0.38, dampingFraction: 0.8)
}

private struct ChatSendRiseModifier: ViewModifier {
  let offsetY: CGFloat
  let scale: CGFloat
  let opacity: Double

  func body(content: Content) -> some View {
    content
      .offset(y: offsetY)
      .scaleEffect(scale, anchor: .bottomTrailing)
      .opacity(opacity)
  }
}

extension AnyTransition {
  /// Insertion only. A removal that flew back down would animate history
  /// pruning and conversation switches, which are not sends.
  static var chatSendRise: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: ChatSendRiseModifier(
          offsetY: ChatSendMotion.riseDistance,
          scale: ChatSendMotion.enteringScale,
          opacity: 0
        ),
        identity: ChatSendRiseModifier(offsetY: 0, scale: 1, opacity: 1)
      ),
      removal: .opacity
    )
  }
}

/// Pure decision for the conversation-switch scroll-state reset. Extracted from
/// the (generic) view so it is unit-testable and so switching between two
/// conversations through a transient empty timeline (A -> nil -> B) still
/// resets session-scoped scroll state for B.
enum ChatConversationSwitch {
  /// - Parameters:
  ///   - tracked: the conversation id currently being tracked.
  ///   - newId: the incoming `messages.first?.id` (nil while empty/loading).
  /// - Returns: the id to track next, and whether to reset session state.
  ///   A nil incoming id keeps tracking the previous conversation (so the
  ///   reset fires when the real conversation arrives) and never resets;
  ///   a real incoming id resets only when a previous conversation existed
  ///   (never on the initial population).
  static func transition(current tracked: String?, incoming newId: String?)
    -> (newTracked: String?, shouldReset: Bool)
  {
    guard let newId, newId != tracked else { return (tracked, false) }
    return (newId, tracked != nil)
  }
}

/// Reusable chat messages scroll view extracted from ChatPage.
/// Used by both ChatPage (main chat) and TaskChatPanel (task sidebar chat).
struct ChatMessagesView<WelcomeContent: View>: View {
  let messages: [ChatMessage]
  let isSending: Bool
  let hasMoreMessages: Bool
  let isLoadingMoreMessages: Bool
  let isLoadingInitial: Bool
  let app: OmiApp?
  let onLoadMore: () async -> Void
  let onRate: (String, Int?) -> Void
  var onCitationTap: ((Citation) -> Void)? = nil
  var sessionsLoadError: String? = nil
  var onRetry: (() -> Void)? = nil
  /// Token that increments each time the local user sends a message.
  /// ChatMessagesView uses this to follow the latest message immediately
  /// after the local user row is inserted.
  /// Pass nil when the caller cannot distinguish local sends (e.g. TaskChatPanel
  /// with its own send path).
  var localSendToken: LocalSendToken? = nil
  /// Fired when the user taps Cancel on a stalled-tool banner.
  /// Threaded down to `ToolCallsGroup`. Optional so existing callers
  /// don't need updating; ChatPage passes `chatProvider.stopAgent`.
  var onCancelTurn: (() -> Void)? = nil
  /// Opens a spawned background-agent pill from a `spawn_agent` tool row.
  /// Optional so task/sidebar chat callers that do not expose floating pills
  /// keep the existing non-clickable tool-card behavior.
  /// Completion reports whether the agent was resolved and presented.
  var onOpenAgent: ((UUID, @escaping (Bool) -> Void) -> Void)? = nil
  /// Opens via structured agent identity (session/run/pill) when available.
  var onOpenAgentRef: ((AgentTimelineRef, @escaping (Bool) -> Void) -> Void)? = nil
  /// Horizontal inset of the message column. Home passes 0 so bubbles align
  /// exactly with the ask bar's edges; other surfaces keep the default gutter.
  var horizontalContentPadding: CGFloat = OmiSpacing.xxl
  /// Vertical transcript inset. Home uses a tighter value because its page
  /// shell already provides the breathing room beneath the floating top bar.
  var verticalContentPadding: CGFloat = OmiSpacing.xl
  /// Extra trailing inset only. Home passes a small value so the macOS overlay
  /// scrollbar doesn't clip right-aligned user pills when horizontalContentPadding
  /// is 0; the left edge stays aligned with the ask bar. Default 0.
  var trailingContentPadding: CGFloat = 0
  @ViewBuilder var welcomeContent: () -> WelcomeContent

  /// IDs of messages that duplicate an earlier message in the same session.
  ///
  /// Held in state rather than recomputed in `body`. The fingerprint copies the
  /// full text of every long message, and `body` re-evaluates on every frame of
  /// a paced reveal — deriving this inline made the transcript pay for its own
  /// whole history 30 times a second while omi was answering.
  @State private var duplicateMessageIds: Set<String> = []

  // MARK: - Scroll State

  @State private var isUserAtBottom = true
  /// Source of truth for scroll intent. Geometry/layout changes alone must NOT
  /// switch this to `.freeScrolling` — only physical user input (wheel/trackpad,
  /// mouse, or keyboard scroll-navigation).
  @State private var scrollMode: ChatScrollMode = .followingBottom
  /// Throttle token for scrollToBottom — prevents the streaming + scroll
  /// detection feedback loop from saturating the main thread.
  @State private var scrollThrottleWorkItem: DispatchWorkItem?
  /// True when the user is actively scrolling via scroll wheel/trackpad.
  /// Set immediately by the scroll wheel monitor to win the race against
  /// throttled programmatic scrolls during streaming.
  @State private var userIsScrolling = false
  @State private var userScrollEndWorkItem: DispatchWorkItem?
  /// Tracks work items for delayed initial bottom scrolls so they can be
  /// canceled on user scroll or disappear.
  @State private var initialScrollWorkItems: [DispatchWorkItem] = []
  // MARK: - Local Send Anchoring

  /// Last observed local send token generation. When it increments, we know
  /// a local user send just happened and can anchor the viewport.
  @State private var lastSeenSendGeneration: Int = 0

  // MARK: - Saved Restore

  /// Whether the initial history load for this conversation has been handled.
  /// Prevents repeated initial bottom settling on subsequent messages.count changes.
  @State private var initialRestoreHandled = false
  /// The one deferred initial restore waits for the first transcript layout.
  /// Geometry changes during that interval must not introduce additional
  /// bottom-scroll commands, or saved history visibly flies through the view.
  @State private var isInitialRestorePending = false
  @State private var initialRestoreWorkItem: DispatchWorkItem?

  // MARK: - Prepend Preservation (Load Earlier Messages)

  /// The ID of the first visible message before a "Load earlier" operation.
  /// After load completes, we scroll to reposition this message at the top
  /// of the viewport, preserving the user's reading position.
  @State private var prependAnchorId: String?

  // MARK: - Activity Below Indicator

  /// True when new content arrived while the user is scrolled away, so the
  /// jump-to-bottom affordance should be shown.
  @State private var hasActivityBelow = false

  // MARK: - Conversation Identity

  /// The first message ID of the conversation this view is currently tracking.
  /// Used to detect conversation switches so session-scoped @State can be reset.
  @State private var trackedConversationId: String?

  /// Armed once this transcript has made its first placement. Until then rows
  /// are history being restored, not messages arriving.
  @State private var animatesInsertions = false

  /// Whether the damped live-edge follow is running. Held separately from
  /// `isStreamingReply` because the paced reveal outlives the last token.
  @State private var isFollowingLiveEdge = false

  var body: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .bottom) {
        scrollContent(proxy: proxy)
        scrollToBottomButton(proxy: proxy)
      }
    }
  }

  @ViewBuilder
  private func scrollContent(proxy: ScrollViewProxy) -> some View {
    ScrollView {
      // Row gaps come from `ChatTurnSpacing` per message, not from the stack:
      // a single stack spacing cannot tell "omi answering you" from "a new
      // question starting".
      LazyVStack(spacing: 0) {
        loadMoreButton
        messageContent
        workingIndicator
      }
      // Only a row arriving on a settled transcript animates. A history load
      // populates dozens at once, and springing all of them would turn opening
      // a conversation into a shuffle.
      .animation(
        animatesInsertions ? OmiMotion.gated(ChatSendMotion.insert) : nil,
        value: messages.count
      )
      .padding(.horizontal, horizontalContentPadding)
      .padding(.trailing, trailingContentPadding)
      .padding(.vertical, verticalContentPadding)
      // Do not enable text selection on the whole stack. SelectionOverlay on every
      // chrome Text (agent card headers, tool summaries, timestamps) can peg the
      // main thread in GraphHost layout. Message bodies opt in via OmiMarkdown.
      .background(scrollDetectors)

      // Invisible anchor lives OUTSIDE the LazyVStack so it is always
      // eagerly rendered. Inside LazyVStack it may not exist in the view
      // hierarchy when scrollTo is first called (lazy evaluation), causing
      // the scroll to jump to an estimated — often empty — position.
      if !messages.isEmpty {
        Color.clear
          .frame(height: 1)
          .id("bottom-anchor")
      }
    }
    // MARK: - React to message count changes
    .onChange(of: messages.count) { oldCount, newCount in
      duplicateMessageIds = ChatMessageDeduplicator.duplicateIDs(in: messages)
      handleMessagesCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
    }
    // A reply can only duplicate an earlier one once it has settled, so the
    // other half of the dedup input is the stream ending.
    .onChange(of: isStreamingReply) { _, isStreaming in
      guard !isStreaming else { return }
      duplicateMessageIds = ChatMessageDeduplicator.duplicateIDs(in: messages)
    }
    // A journal restore may be populated by background events while the
    // loader is still collecting its canonical snapshot. Reveal it only after
    // loading completes, then make one initial placement at the live edge.
    .onChange(of: isLoadingInitial) { wasLoading, isLoading in
      guard wasLoading, !isLoading, !messages.isEmpty else { return }
      handleInitialRestore(proxy: proxy)
    }
    // MARK: - React to streaming text changes
    .onChange(of: messages.last?.text) { _, _ in
      handleLiveContentChange(proxy: proxy)
    }
    // MARK: - React to content block changes (tool calls, etc.)
    .onChange(of: messages.last?.contentBlocks.count) { _, _ in
      handleLiveContentChange(proxy: proxy)
    }
    // MARK: - React to local send token (turn anchoring)
    .onChange(of: localSendToken?.generation) { oldGen, newGen in
      guard let newGen = newGen else { return }
      if newGen > lastSeenSendGeneration {
        lastSeenSendGeneration = newGen
        handleLocalSend(proxy: proxy)
      }
    }
    // MARK: - React to isSending (send started)
    .onChange(of: isSending) { oldValue, newValue in
      if newValue && !oldValue && localSendToken == nil {
        cancelAllPendingScrolls()
        userIsScrolling = false
        scrollMode = .followingBottom
        hasActivityBelow = false
        scrollToBottom(proxy: proxy)
      }
    }
    // MARK: - React to isLoadingMoreMessages (prepend preservation)
    .onChange(of: isLoadingMoreMessages) { _, isLoading in
      if isLoading {
        // Capture the first message ID before the load begins
        prependAnchorId = messages.first?.id
      } else {
        // Load finished — restore prepend anchor if user hasn't scrolled
        restorePrependAnchor(proxy: proxy)
      }
    }
    // MARK: - Reset session state on conversation switch
    .onChange(of: messages.first?.id) { _, newId in
      // When the first message ID changes, the user switched to a
      // different conversation (or a new one was loaded). Reset all
      // session-scoped @State so stale tracking doesn't leak across.
      // The decision is delegated to a pure helper so the switch-through-
      // empty transition (A -> nil -> B) is unit-testable and no longer
      // skips the reset for B.
      let transition = ChatConversationSwitch.transition(
        current: trackedConversationId, incoming: newId)
      trackedConversationId = transition.newTracked
      if transition.shouldReset {
        initialRestoreHandled = false
        animatesInsertions = false
        lastSeenSendGeneration = localSendToken?.generation ?? 0
        prependAnchorId = nil
        hasActivityBelow = false
        scrollMode = .followingBottom
        userIsScrolling = false
        isUserAtBottom = true
      }
    }
    // MARK: - Follow a streaming reply on a clock
    //
    // Data events cannot drive the follow. The reveal is paced independently of
    // token arrival, so the transcript keeps growing between flushes and after
    // the last one — this only decides *when* the follower runs, never where it
    // scrolls to.
    .task(id: isStreamingReply) {
      if isStreamingReply {
        isFollowingLiveEdge = true
        return
      }
      try? await Task.sleep(for: .seconds(ChatStreamScroll.settleTail))
      guard !Task.isCancelled else { return }
      isFollowingLiveEdge = false
    }
    .onAppear {
      duplicateMessageIds = ChatMessageDeduplicator.duplicateIDs(in: messages)
      if !isLoadingInitial, !messages.isEmpty {
        handleInitialRestore(proxy: proxy)
      }
    }
    .onDisappear {
      cancelAllPendingScrolls()
    }
  }

  /// Whether omi's reply is still arriving, which is what the follow clock and
  /// the paced reveal both key off.
  private var isStreamingReply: Bool {
    messages.last?.isStreaming == true
  }

  // MARK: - Message Count Change Handler

  /// Central handler for messages.count changes. Handles:
  /// - Initial restore (scroll to latest message on first load)
  /// - New messages arriving while following
  /// - New messages arriving while scrolled away (activity indicator)
  /// - Prepend detection (load earlier)
  private func handleMessagesCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
    // Saved journal rows are not live arrivals. The loading-complete observer
    // above performs their one final placement after the snapshot is visible.
    guard !isLoadingInitial else { return }

    if newCount > oldCount {
      // --- Initial restore: messages went from 0→N ---
      if oldCount == 0 && newCount > 0 {
        handleInitialRestore(proxy: proxy)
        return
      }

      // --- Prepend: new older messages inserted ---
      // If prependAnchorId is set and the count increase corresponds to
      // older messages, the onChange(of: isLoadingMoreMessages) handler
      // takes care of repositioning.

      // --- New live messages arriving ---
      if scrollMode == .followingBottom {
        scrollToBottom(proxy: proxy)
      } else {
        // freeScrolling — new content arrived below
        hasActivityBelow = true
      }
    }
  }

  private func handleLiveContentChange(proxy: ScrollViewProxy) {
    guard !isLoadingInitial else { return }

    switch scrollMode {
    case .followingBottom:
      // The damped follower owns the offset whenever it is running, including
      // through the settle tail after the last token. A commanded scroll on top
      // of it would assign an offset the follower is mid-way through
      // integrating, which is a visible snap.
      guard !isFollowingLiveEdge else { return }
      throttledScrollToBottom(proxy: proxy)
    case .freeScrolling:
      hasActivityBelow = true
    }
  }

  // MARK: - Initial Restore

  /// On the first load of a saved conversation, follow the latest message.
  /// Chat surfaces should open at the live edge; if the reader wants older
  /// context, explicit scroll input switches the mode to free-scrolling.
  private func handleInitialRestore(proxy: ScrollViewProxy) {
    guard !initialRestoreHandled else { return }
    initialRestoreHandled = true

    scrollMode = .followingBottom
    hasActivityBelow = false
    isInitialRestorePending = true

    let work = DispatchWorkItem { [self] in
      defer {
        isInitialRestorePending = false
        initialRestoreWorkItem = nil
        animatesInsertions = true
      }
      guard scrollMode == .followingBottom, !userIsScrolling else { return }
      scrollToBottom(proxy: proxy)
    }
    initialRestoreWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  // MARK: - Local Send / Turn Anchoring

  /// Called when the local send token increments. Follow the latest message
  /// so the newly inserted user row and streamed assistant response stay in
  /// view unless the user explicitly scrolls away.
  private func handleLocalSend(proxy: ScrollViewProxy) {
    guard !messages.isEmpty else { return }

    cancelAllPendingScrolls()
    scrollMode = .followingBottom
    hasActivityBelow = false
    userIsScrolling = false
    scrollToBottom(proxy: proxy)
    scheduleInitialScroll(proxy: proxy, delay: 0.1)
  }

  // MARK: - Prepend Preservation

  /// After "Load earlier messages" completes, scroll to restore the message
  /// that was at the top before the load. Skipped if the user scrolled during
  /// the load or if the anchor message is no longer present.
  private func restorePrependAnchor(proxy: ScrollViewProxy) {
    guard let anchorId = prependAnchorId else { return }
    prependAnchorId = nil

    // Only bail if the user is *physically* scrolling right now — not on
    // scrollMode. Prepend ("Load earlier") only happens while reading history,
    // i.e. scrollMode == .freeScrolling, so guarding on that mode made this
    // restore (and the scrollTo below) dead code — the viewport jumped on every
    // page-up. userIsScrolling is the real "don't fight the user's drag" signal
    // (set by UserScrollDetector on any scroll interaction — wheel, drag, or
    // keyboard scroll — and auto-cleared 0.3s after the last one).
    guard !userIsScrolling else { return }

    // Verify the anchor message is still in the list
    let stillExists = messages.contains { $0.id == anchorId }
    guard stillExists else { return }

    // Scroll anchor to top without animation
    let work = DispatchWorkItem { [self] in
      guard !self.userIsScrolling else { return }
      proxy.scrollTo(anchorId, anchor: .top)
    }
    initialScrollWorkItems.append(work)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  // MARK: - Scheduled Scrolls

  /// Schedules a delayed bottom scroll that is mode-aware and cancelable.
  private func scheduleInitialScroll(proxy: ScrollViewProxy, delay: TimeInterval) {
    var workItem: DispatchWorkItem?
    workItem = DispatchWorkItem { [self] in
      // Only fire if still following — user may have scrolled during settling
      if scrollMode == .followingBottom {
        scrollToBottom(proxy: proxy)
      }
      if let workItem {
        initialScrollWorkItems.removeAll { $0 === workItem }
      }
    }
    if let workItem {
      initialScrollWorkItems.append(workItem)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
  }

  /// Cancels all pending scheduled scrolls (throttle, initial, user-scroll-end).
  private func cancelAllPendingScrolls() {
    scrollThrottleWorkItem?.cancel()
    scrollThrottleWorkItem = nil
    userScrollEndWorkItem?.cancel()
    userScrollEndWorkItem = nil
    initialRestoreWorkItem?.cancel()
    initialRestoreWorkItem = nil
    isInitialRestorePending = false
    for item in initialScrollWorkItems {
      item.cancel()
    }
    initialScrollWorkItems.removeAll()
  }

  // MARK: - Subviews

  @ViewBuilder
  private var loadMoreButton: some View {
    if hasMoreMessages {
      Button {
        prependAnchorId = messages.first?.id
        Task {
          await onLoadMore()
        }
      } label: {
        if isLoadingMoreMessages {
          ProgressView()
            .scaleEffect(0.8)
        } else {
          Text("Load earlier messages")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .padding(.vertical, OmiSpacing.sm)
    }
  }

  @ViewBuilder
  private var messageContent: some View {
    if isLoadingInitial && sessionsLoadError == nil {
      VStack(spacing: OmiSpacing.md) {
        ProgressView()
          .scaleEffect(0.8)
        Text("Loading...")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textTertiary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 80)
    } else if let error = sessionsLoadError, messages.isEmpty {
      errorContent(error: error)
    } else if messages.isEmpty {
      welcomeContent()
    } else {
      let dupeIds = duplicateMessageIds
      let displayMessages = AgentLifecycleDisplayProjection.project(messages)
      ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
        ChatBubble(
          message: message,
          app: app,
          onRate: { rating in
            onRate(message.id, rating)
          },
          onCitationTap: { citation in
            onCitationTap?(citation)
          },
          isDuplicate: dupeIds.contains(message.id),
          onCancelTurn: onCancelTurn,
          onOpenAgent: onOpenAgent,
          onOpenAgentRef: onOpenAgentRef
        )
        .padding(
          .top,
          ChatTurnSpacing.leadingGap(
            previous: index > 0 ? displayMessages[index - 1].sender : nil,
            current: message.sender
          )
        )
        // Omi's row is a text block that grows, not a thing that arrives — it
        // is inserted empty and fills in, so only the user's own turn rises.
        .transition(message.sender == .user ? .chatSendRise : .opacity)
        .id(message.id)
      }
    }
  }

  /// Omi's mark at the foot of the transcript. It is mounted here rather than
  /// inside the streaming bubble for two reasons: it shows before the reply has
  /// any row of its own, and it stays after the reply lands, turning slowly, so
  /// omi is present on the surface rather than only while it is busy.
  ///
  /// The empty state has its own hero mark, so this one waits for a transcript.
  @ViewBuilder
  private var workingIndicator: some View {
    if !messages.isEmpty || isSending {
      ChatWorkingIndicator(
        label: isSending ? ChatWorkingStatus.label(for: messages.last) : nil,
        motion: ChatWorkingStatus.motion(for: messages.last)
      )
      .padding(.top, ChatTurnSpacing.withinTurn)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func errorContent(error: String) -> some View {
    VStack(spacing: OmiSpacing.lg) {
      Image(systemName: "exclamationmark.triangle")
        .scaledFont(size: OmiType.hero)
        .foregroundColor(OmiColors.warning)

      Text("Failed to load chats")
        .scaledFont(size: OmiType.subheading, weight: .medium)
        .foregroundColor(OmiColors.textPrimary)

      Text(error)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textTertiary)
        .multilineTextAlignment(.center)

      if let onRetry {
        Button(action: onRetry) {
          Text("Try Again")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)
            .padding(.horizontal, OmiSpacing.xl)
            .padding(.vertical, OmiSpacing.sm)
            .omiControlSurface(fill: OmiColors.userBubble, radius: OmiChrome.chipRadius)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(OmiSpacing.section)
    .padding(.vertical, 48)
  }

  // Both detectors share the same .background so their NSViews land
  // inside NSScrollView.documentView — the superview walk in each
  // coordinator then correctly finds the enclosing NSScrollView.
  private var scrollDetectors: some View {
    ZStack {
      // Mounted alongside the detectors so its superview walk finds the same
      // enclosing NSScrollView they do.
      ChatLiveEdgeFollower(isActive: isFollowingLiveEdge) {
        scrollMode == .followingBottom && !userIsScrolling
      }
      ScrollPositionDetector { atBottom in
        isUserAtBottom = atBottom
        // Resume live following when the reader scrolls back to the
        // live edge. atBottom == true is unambiguous intent to follow
        // again; only atBottom == false is ambiguous (it can be a
        // geometry/layout change, not user intent) and must NOT switch
        // to .freeScrolling on its own.
        if atBottom && scrollMode == .freeScrolling {
          cancelAllPendingScrolls()
          userIsScrolling = false
          scrollMode = .followingBottom
          hasActivityBelow = false
        }
      }
      UserScrollDetector {
        scrollMode = .freeScrolling
        userIsScrolling = true
        hasActivityBelow = false
        cancelAllPendingScrolls()
        let endWork = DispatchWorkItem {
          userIsScrolling = false
        }
        userScrollEndWorkItem = endWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: endWork)
      } onScrollSettledAtBottom: {
        guard scrollMode == .freeScrolling else { return }
        cancelAllPendingScrolls()
        userIsScrolling = false
        scrollMode = .followingBottom
        hasActivityBelow = false
      }
    }
  }

  @ViewBuilder
  private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
    // Show when free-scrolled AND there are messages, AND either there's
    // activity below or we're in a non-following mode.
    if scrollMode == .freeScrolling && !messages.isEmpty {
      Button {
        cancelAllPendingScrolls()
        userIsScrolling = false
        scrollMode = .followingBottom
        hasActivityBelow = false
        scrollToBottom(proxy: proxy)
      } label: {
        // A compact opaque chip rather than a bare glyph: it floats over live
        // text, so it has to read as chrome instead of settling into the words
        // underneath it.
        Image(systemName: "arrow.down")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(OmiColors.textSecondary)
          .frame(width: 28, height: 28)
          .background(Circle().fill(OmiColors.backgroundPrimary))
          .overlay(
            Circle()
              .stroke(Color.white.opacity(hasActivityBelow ? 0.30 : 0.12), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
          .contentShape(Circle())
          .scaleEffect(hasActivityBelow ? 1.06 : 1.0)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Jump to latest message")
      .padding(.bottom, OmiSpacing.sm)
      .transition(.scale.combined(with: .opacity))
      .omiAnimation(.easeInOut(duration: 0.2), value: scrollMode)
      .omiAnimation(.easeInOut(duration: 0.3), value: hasActivityBelow)
    }
  }

  private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
    guard scrollMode == .followingBottom else { return }
    // Don't fight the user — skip if they're actively wheel/trackpad scrolling
    guard !userIsScrolling else { return }
    guard !messages.isEmpty else { return }
    guard animated else {
      proxy.scrollTo("bottom-anchor", anchor: .bottom)
      return
    }
    OmiMotion.withGated(ChatStreamScroll.animation) {
      proxy.scrollTo("bottom-anchor", anchor: .bottom)
    }
  }

  /// Throttled version of scrollToBottom, for content that arrives whole: a
  /// tool card, a resource strip, a citation row. Those add their height in one
  /// step, so a short animated move reads better than a jump — unlike a paced
  /// reveal, which the pin in the follow task owns instead.
  private func throttledScrollToBottom(proxy: ScrollViewProxy) {
    guard !userIsScrolling else { return }
    // Cancel any pending scroll — we'll schedule a fresh one
    scrollThrottleWorkItem?.cancel()
    let workItem = DispatchWorkItem { [self] in
      scrollToBottom(proxy: proxy, animated: true)
    }
    scrollThrottleWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + ChatStreamScroll.throttle, execute: workItem)
  }
}
