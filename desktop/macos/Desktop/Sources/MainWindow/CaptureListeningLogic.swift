import SwiftUI

/// How the Listening chip reads. `HomeStatusState` distinguishes only
/// on/off/blocked, but "on" covers two very different realities: audio is
/// flowing, or the capture gate is shut and the microphone is stopped until a
/// call is detected. The second one is the shipped default ("Only during
/// meetings"), so painting it the same green as a live recording is the app
/// claiming to listen while it is muted, so it gets its own case.
enum ListeningChipState: Equatable {
  /// Audio is being captured right now.
  case capturing
  /// Listening is on, but the meeting gate is shut: no microphone, no audio.
  case standby
  case off
  /// The transcription service reported an error; nothing can be captured.
  case blocked

  /// The nearest `HomeStatusState`. `standby` deliberately maps to `.inactive`:
  /// the shared chip paints `.active` green, and green must mean audio.
  var statusState: HomeStatusState {
    switch self {
    case .capturing:
      return .active
    case .standby, .off:
      return .inactive
    case .blocked:
      return .blocked
    }
  }

  /// Filled waveform only while audio is actually flowing; the hollow one reads
  /// as "the microphone is here, it just isn't running".
  var systemImage: String {
    switch self {
    case .capturing:
      return "waveform.circle.fill"
    case .standby:
      return "waveform.circle"
    case .off:
      return "mic.circle"
    case .blocked:
      return "exclamationmark.triangle.fill"
    }
  }

  /// Tooltip/VoiceOver wording. `blocked` carries the failure here rather than
  /// in the chip title so the control cluster keeps its width.
  var statusText: String {
    switch self {
    case .capturing:
      return "Recording"
    case .standby:
      return "Paused"
    case .off:
      return "Off"
    case .blocked:
      return "Transcription unavailable"
    }
  }
}

/// One row of the listening-mode picker. The hover reveal, the right-click menu
/// and the VoiceOver cycle all render from the same list, so the three surfaces
/// cannot disagree about which modes exist or which one is current.
struct ListeningModeOption: Identifiable {
  let mode: AssistantSettings.SystemAudioCaptureMode
  let title: String
  let detail: String
  let isCurrent: Bool

  /// Titles are unique per mode, which keeps the identity a plain string.
  var id: String { title }
}

/// Capture/Listening control logic for the persistent status bar
/// (`CaptureListeningControls`), which is the only copy the app renders.
/// `DashboardPage.homeHeader` is a retired second copy with no call site and is
/// the reason the status derivations live here rather than in a view.
///
/// The chip state derives from the same flags the capture gate itself sets, so
/// what the pill claims and what the microphone is doing cannot drift. Each view
/// keeps its own `@State`/`@AppStorage` — preserving SwiftUI ownership and
/// reactivity — and passes them in as values and bindings.
@MainActor
enum CaptureListeningLogic {
  // MARK: Status derivations

  static func captureStatus(appState: AppState, isCaptureMonitoring: Bool) -> HomeStatusState {
    if appState.isScreenCaptureKitBroken || appState.isScreenRecordingStale || !appState.hasScreenRecordingPermission {
      return .blocked
    }
    return isCaptureLive(isCaptureMonitoring: isCaptureMonitoring) ? .active : .inactive
  }

  static func isCaptureLive(isCaptureMonitoring: Bool) -> Bool {
    isCaptureMonitoring || ProactiveAssistantsPlugin.shared.isMonitoring
  }

  static func listeningCaptureMode(raw: String) -> AssistantSettings.SystemAudioCaptureMode {
    AssistantSettings.SystemAudioCaptureMode(rawValue: raw) ?? .onlyDuringMeetings
  }

  /// The chip's truth: enabled is not the same as capturing. `isAwaitingMeeting`
  /// is the same flag the capture gate sets when it stops the microphone, so the
  /// chip and the audio pipeline cannot drift apart.
  static func listeningChipState(appState: AppState) -> ListeningChipState {
    listeningChipState(
      isTranscribing: appState.isTranscribing,
      isAwaitingMeeting: appState.isAwaitingMeeting,
      hasServiceError: appState.transcriptionServiceError != nil
    )
  }

  nonisolated static func listeningChipState(
    isTranscribing: Bool, isAwaitingMeeting: Bool, hasServiceError: Bool
  ) -> ListeningChipState {
    // A service error outranks the toggle: nothing is being transcribed either
    // way, and the error is the actionable fact.
    if hasServiceError { return .blocked }
    guard isTranscribing else { return .off }
    return isAwaitingMeeting ? .standby : .capturing
  }

  /// The mode's own name, used wherever the mode is named rather than described.
  nonisolated static func listeningModeName(
    _ mode: AssistantSettings.SystemAudioCaptureMode
  ) -> String {
    switch mode {
    case .always:
      return "Always"
    case .onlyDuringMeetings:
      return "Meetings only"
    case .never:
      return "Mic only"
    }
  }

  nonisolated static func listeningModeDetail(
    _ mode: AssistantSettings.SystemAudioCaptureMode
  ) -> String {
    switch mode {
    case .always:
      return "Mic and app audio stay on."
    case .onlyDuringMeetings:
      return "Mic stays off until a call starts."
    case .never:
      return "Mic only, app audio is never recorded."
    }
  }

  static func listeningModeTitle(appState: AppState, raw: String) -> String {
    listeningModeTitle(
      mode: listeningCaptureMode(raw: raw),
      isTranscribing: appState.isTranscribing,
      isAwaitingMeeting: appState.isAwaitingMeeting
    )
  }

  /// What the chip says about the mode. With Listening switched off no mode is
  /// doing anything, so the title falls back to naming the mode instead of
  /// describing a capture state that isn't happening.
  nonisolated static func listeningModeTitle(
    mode: AssistantSettings.SystemAudioCaptureMode, isTranscribing: Bool, isAwaitingMeeting: Bool
  ) -> String {
    guard isTranscribing else { return listeningModeName(mode) }
    switch mode {
    case .always:
      return "Always"
    case .onlyDuringMeetings:
      return isAwaitingMeeting ? "Waiting for a meeting" : "In meeting"
    case .never:
      return "Mic only"
    }
  }

  /// The short label the chip prints next to "Listening". Always-on needs no
  /// badge, being the one state where the title alone is the whole truth.
  nonisolated static func listeningModeBadge(
    mode: AssistantSettings.SystemAudioCaptureMode, isTranscribing: Bool, isAwaitingMeeting: Bool
  ) -> String? {
    switch mode {
    case .always:
      return nil
    case .onlyDuringMeetings:
      return isTranscribing && !isAwaitingMeeting ? "In meeting" : "Meetings only"
    case .never:
      return "Mic only"
    }
  }

  /// The retired listening-mode title. Never called since the chip started
  /// deriving its label from the capture gate; it stays in-tree so its removal
  /// can be its own reviewable change. It answers "In meeting" whenever the mode
  /// is `.onlyDuringMeetings` and nothing is pending, including while Listening
  /// is switched off entirely, since the gate forces `isAwaitingMeeting` false
  /// when there is no session to gate.
  static func retiredListeningModeTitle(appState: AppState, raw: String) -> String {
    switch listeningCaptureMode(raw: raw) {
    case .always:
      return "Always"
    case .onlyDuringMeetings:
      return appState.isAwaitingMeeting ? "Meetings only" : "In meeting"
    case .never:
      return "Mic only"
    }
  }

  // MARK: Mode selection

  /// The modes in picker order, most open first, so the list itself reads as
  /// "how much Omi hears".
  nonisolated static var listeningModes: [AssistantSettings.SystemAudioCaptureMode] {
    [.always, .onlyDuringMeetings, .never]
  }

  nonisolated static func listeningModeOptions(
    current: AssistantSettings.SystemAudioCaptureMode
  ) -> [ListeningModeOption] {
    listeningModes.map { mode in
      ListeningModeOption(
        mode: mode,
        title: listeningModeName(mode),
        detail: listeningModeDetail(mode),
        isCurrent: mode == current
      )
    }
  }

  /// Wraps through every mode. Hover reveals are invisible to Full Keyboard
  /// Access and VoiceOver, so those paths advance one step at a time instead,
  /// which is the only way they reach the third mode at all.
  nonisolated static func nextListeningMode(
    after mode: AssistantSettings.SystemAudioCaptureMode
  ) -> AssistantSettings.SystemAudioCaptureMode {
    let modes = listeningModes
    let index = modes.firstIndex(of: mode) ?? modes.count - 1
    return modes[(index + 1) % modes.count]
  }

  // MARK: Actions

  static func toggleListening(
    appState: AppState, transcriptionEnabled: Binding<Bool>, isTogglingListening: Binding<Bool>
  ) {
    let enabled = !appState.isTranscribing
    if enabled && !appState.hasMicrophonePermission {
      appState.requestMicrophonePermission()
      return
    }

    isTogglingListening.wrappedValue = true
    transcriptionEnabled.wrappedValue = enabled
    AssistantSettings.shared.transcriptionEnabled = enabled
    AnalyticsManager.shared.settingToggled(setting: "transcription", enabled: enabled)
    NotificationCenter.default.post(
      name: .toggleTranscriptionRequested,
      object: nil,
      userInfo: ["enabled": enabled]
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      isTogglingListening.wrappedValue = false
    }
  }

  static func toggleListeningMode(raw: Binding<String>) {
    let nextMode: AssistantSettings.SystemAudioCaptureMode =
      listeningCaptureMode(raw: raw.wrappedValue) == .onlyDuringMeetings ? .always : .onlyDuringMeetings
    raw.wrappedValue = nextMode.rawValue
    AssistantSettings.shared.systemAudioCaptureMode = nextMode
    AnalyticsManager.shared.settingToggled(
      setting: "meetings_only_listening",
      enabled: nextMode == .onlyDuringMeetings
    )
  }

  /// Selects a mode outright. The two-way `toggleListeningMode` can only swap
  /// between "Always" and "Meetings only"; every surface that offers all three
  /// goes through here. Persisting posts `.systemAudioCaptureModeDidChange`, so
  /// an in-progress recording re-applies the gate immediately.
  static func setListeningMode(_ mode: AssistantSettings.SystemAudioCaptureMode, raw: Binding<String>) {
    guard listeningCaptureMode(raw: raw.wrappedValue) != mode else { return }
    raw.wrappedValue = mode.rawValue
    AssistantSettings.shared.systemAudioCaptureMode = mode
    AnalyticsManager.shared.settingToggled(
      setting: "meetings_only_listening",
      enabled: mode == .onlyDuringMeetings
    )
  }

  static func cycleListeningMode(raw: Binding<String>) {
    setListeningMode(nextListeningMode(after: listeningCaptureMode(raw: raw.wrappedValue)), raw: raw)
  }

  static func toggleCapture(
    appState: AppState, screenAnalysisEnabled: Binding<Bool>, isCaptureMonitoring: Binding<Bool>,
    isTogglingCapture: Binding<Bool>
  ) {
    syncCaptureState(screenAnalysisEnabled: screenAnalysisEnabled, isCaptureMonitoring: isCaptureMonitoring)
    let enabled = !isCaptureLive(isCaptureMonitoring: isCaptureMonitoring.wrappedValue)
    isTogglingCapture.wrappedValue = true

    if enabled {
      ProactiveAssistantsPlugin.shared.refreshScreenRecordingPermission()
      guard ProactiveAssistantsPlugin.shared.hasScreenRecordingPermission else {
        screenAnalysisEnabled.wrappedValue = false
        isCaptureMonitoring.wrappedValue = false
        isTogglingCapture.wrappedValue = false
        ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
        return
      }
    }

    screenAnalysisEnabled.wrappedValue = enabled
    AssistantSettings.shared.screenAnalysisEnabled = enabled
    AnalyticsManager.shared.settingToggled(setting: "monitoring", enabled: enabled)

    if enabled {
      ProactiveAssistantsPlugin.shared.startMonitoring { success, _ in
        DispatchQueue.main.async {
          isTogglingCapture.wrappedValue = false
          isCaptureMonitoring.wrappedValue = ProactiveAssistantsPlugin.shared.isMonitoring
          if !success {
            screenAnalysisEnabled.wrappedValue = false
            AssistantSettings.shared.screenAnalysisEnabled = false
            isCaptureMonitoring.wrappedValue = false
          }
        }
      }
    } else {
      ProactiveAssistantsPlugin.shared.stopMonitoring()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        isTogglingCapture.wrappedValue = false
        isCaptureMonitoring.wrappedValue = false
      }
    }
  }

  static func syncCaptureState(screenAnalysisEnabled: Binding<Bool>, isCaptureMonitoring: Binding<Bool>) {
    ProactiveAssistantsPlugin.shared.refreshScreenRecordingPermission()
    screenAnalysisEnabled.wrappedValue = AssistantSettings.shared.screenAnalysisEnabled
    isCaptureMonitoring.wrappedValue = ProactiveAssistantsPlugin.shared.isMonitoring
  }
}
