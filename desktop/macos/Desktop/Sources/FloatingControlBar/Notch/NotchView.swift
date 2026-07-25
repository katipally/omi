import OmiTheme
import SwiftUI

/// Root view for one notch panel. The window frame is fixed; this view derives
/// a `NotchPresentation` and animates ONLY the inner content frame + corner
/// radii, anchored `.top` so every expansion grows out of the camera housing.
struct NotchView: View {
  @ObservedObject var vm: NotchViewModel
  @EnvironmentObject var barState: FloatingControlBarState
  @ObservedObject private var agents = AgentPillsManager.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isHovering = false
  /// Esc key monitors, live only while a reply lingers (zero idle cost).
  @State private var lingerEscMonitors: [Any] = []

  // MARK: - Presentation ladder

  /// Single value that both the panel size and the rendered content derive
  /// from. Priority:
  /// listening > thinking > responding > hint > notification > idle.
  private var presentation: NotchPresentation {
    let base = NotchPresentation.derive(
      // The RAW listening phase. `isVoiceListening` folds the hint in, so
      // deriving from it makes every PTT error render as "Listening...".
      isListening: barState.isListeningPhase,
      isThinking: barState.isThinking,
      isResponding: barState.isVoiceResponseActive,
      hintText: barState.pttHintText.isEmpty ? barState.transientHintText : barState.pttHintText,
      notificationID: barState.currentNotification?.id
    )
    // A finished reply lingers for a few seconds after the turn ends. heldReply
    // is set while the response streams, so this is already true the instant
    // the response goes inactive — the notch never collapses to idle first.
    if vm.isLingeringReply {
      switch base {
      case .idle, .notification: return .responding
      default: return base
      }
    }
    return base
  }

  // MARK: - Animations (two isolated timelines)

  /// Discrete morphs between presentations. Springs. The expanded voice states
  /// grow with the open spring; the compact thinking pill and the passive
  /// surfaces settle with the close spring.
  private var morphAnimation: Animation {
    if reduceMotion { return NotchAnimation.reduced }
    switch presentation {
    case .listening, .responding: return NotchAnimation.open
    case .idle, .thinking, .hint, .notification: return NotchAnimation.close
    }
  }

  /// Continuous auto-grow while an answer streams. Calm, no spring bounce.
  /// Deliberately isolated from the morph timeline: keying the morph spring on
  /// the measured height makes the measure -> resize -> remeasure loop
  /// oscillate.
  private var heightAnimation: Animation {
    reduceMotion ? NotchAnimation.reduced : .smooth(duration: 0.35)
  }

  private var contentTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
  }

  private var displayedSize: CGSize { vm.size(for: presentation) }

  private var topCornerRadius: CGFloat {
    presentation.isExpandedSurface ? NotchMetrics.cornerOpen.top : NotchMetrics.cornerClosed.top
  }

  private var bottomCornerRadius: CGFloat {
    presentation.isExpandedSurface ? NotchMetrics.cornerOpen.bottom : NotchMetrics.cornerClosed.bottom
  }

  // MARK: - Body

  var body: some View {
    notchBody
      .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
      // Capture the reply as it streams so the linger is ready the moment the
      // response ends (prevents a one-frame collapse to idle).
      .onChange(of: barState.liveVoiceAssistantText) { _, reply in
        vm.noteReply(reply)
      }
      // A new turn starts fresh: reset the measured height and drop any
      // lingering reply from the previous turn.
      .onChange(of: barState.isListeningPhase) { _, listening in
        if listening { vm.resetReply() }
      }
      // Turn ended: start the linger dismissal countdown (hovering pauses it).
      // No captured reply -> just settle back to idle.
      .onChange(of: barState.isVoicePresentationActive) { _, active in
        guard !active else { return }
        if vm.heldReply.isEmpty {
          vm.voiceBodyHeight = nil
        } else {
          vm.beginReplyDismiss()
        }
      }
      // Esc dismisses a lingering reply. The notch is non-activating and never
      // key, so a window-level handler would never see Esc; watch for it while
      // (and only while) a reply lingers.
      .onChange(of: vm.isLingeringReply) { _, lingering in
        if lingering { installLingerEscMonitors() } else { removeLingerEscMonitors() }
      }
      .onDisappear { removeLingerEscMonitors() }
  }

  private func installLingerEscMonitors() {
    removeLingerEscMonitors()
    // The local monitor RETURNS the event rather than swallowing it. Eating Esc
    // app-wide for the duration of a linger would break Esc in the main window's
    // sheets and pickers, which is a far worse bug than an Esc that both
    // dismisses the reply and closes a sheet.
    let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.keyCode == 53 else { return event }
      MainActor.assumeIsolated { vm.dismissReply() }
      return event
    }
    // Global monitors need Accessibility / Input Monitoring permission. Without
    // it this is silently inert, so Esc-while-another-app-is-frontmost is
    // best-effort; the linger still times out on its own.
    let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      guard event.keyCode == 53 else { return }
      MainActor.assumeIsolated { vm.dismissReply() }
    }
    lingerEscMonitors = [local, global].compactMap { $0 }
  }

  private func removeLingerEscMonitors() {
    for monitor in lingerEscMonitors { NSEvent.removeMonitor(monitor) }
    lingerEscMonitors = []
  }

  /// The black island is its OWN stable layer: a NotchShape fill whose frame
  /// always interpolates (no conditional content inside, so its identity can
  /// never break). The presentation-switched content crossfades ON TOP, clipped
  /// to the same shape — the Dynamic Island grammar: the black mass grows, the
  /// content swaps inside it.
  private var notchBody: some View {
    ZStack(alignment: .top) {
      NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
        .fill(Color.black)
        .frame(width: displayedSize.width, height: displayedSize.height)
        // 1pt seam hider: the top fillets must never reveal a hairline gap
        // against the physical black notch / bezel.
        .overlay(alignment: .top) {
          Rectangle()
            .fill(.black)
            .frame(height: 1)
            .padding(.horizontal, topCornerRadius)
        }
        .shadow(
          color: (isHovering || presentation.isExpandedSurface) ? .black.opacity(0.7) : .clear,
          radius: 8
        )
      bodyContent
        .frame(width: displayedSize.width, height: displayedSize.height, alignment: .top)
        .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
      // The Omi orb is rendered once across the whole voice turn so it morphs
      // in place (waveform -> ring -> waveform) instead of cross-fading. It
      // sits just below the camera housing, centered.
      voiceOrbLayer
    }
    .animation(morphAnimation, value: presentation)
    .animation(heightAnimation, value: vm.voiceBodyHeight)
    .contentShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
    .onHover(perform: handleHover)
    .contextMenu {
      Button("Disable for 2 hours") {
        FloatingControlBarManager.shared.snooze(for: 2 * 60 * 60)
      }
    }
  }

  @ViewBuilder
  private var bodyContent: some View {
    switch presentation {
    case .listening:
      NotchVoiceView(
        placeholder: "Listening…",
        onOpenApp: nil,
        followsTail: true,
        topReserve: voiceTopReserve,
        maxBodyHeight: vm.voiceMaxHeight,
        onHeightChange: updateVoiceBodyHeight
      )
      .transition(contentTransition)
    case .thinking:
      // Just the reserved camera + orb space; the orb overlay draws the ring.
      Color.clear
        .frame(height: voiceThinkingReserve)
        .frame(maxWidth: .infinity, alignment: .top)
        .transition(contentTransition)
    case .responding:
      NotchVoiceView(
        text: respondingText,
        onOpenApp: { MainWindowReveal.activate() },
        followsTail: barState.isVoiceResponseActive,
        topReserve: voiceTopReserve,
        maxBodyHeight: vm.voiceMaxHeight,
        onHeightChange: updateVoiceBodyHeight
      )
      .transition(contentTransition)
    case .hint(let text):
      VStack(spacing: 2) {
        closedChrome
        Text(text)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundStyle(.white.opacity(0.75))
          .lineLimit(1)
          .padding(.horizontal, OmiSpacing.md)
      }
      .transition(contentTransition)
    case .notification(let id):
      VStack(spacing: NotchMetrics.notificationSpacing) {
        closedChrome
        if let notification = barState.currentNotification, notification.id == id {
          NotchNotificationCard(notification: notification)
        }
      }
      .transition(contentTransition)
    case .idle:
      closedChrome
    }
  }

  // MARK: - Voice orb (one instance across the whole turn, morphs in place)

  /// Height reserved for the morphing orb below the camera housing.
  private var voiceOrbHeight: CGFloat { 30 }
  private var voiceOrbTopGap: CGFloat { 4 }
  /// Space above the transcript: camera strip + gap + orb + breathing room
  /// before the text. Matches the orb overlay's top offset.
  private var voiceTopReserve: CGFloat {
    vm.closedNotchSize.height + voiceOrbTopGap + voiceOrbHeight + OmiSpacing.lg
  }
  /// Thinking has no text — just the camera strip + orb.
  private var voiceThinkingReserve: CGFloat {
    vm.closedNotchSize.height + voiceOrbTopGap + voiceOrbHeight + OmiSpacing.sm
  }

  /// The reply text while responding. Always the held reply (captured live via
  /// noteReply), so the source never switches between streaming and linger —
  /// the reveal just finishes in place with no reload.
  private var respondingText: String { vm.heldReply }

  private var voiceOrbMode: NotchVoiceOrb.Mode {
    if barState.isListeningPhase { return .listening }
    if barState.isThinking { return .thinking }
    if barState.isVoiceResponseActive { return .speaking }
    return .logo  // a finished reply lingering: the Omi mark at rest
  }

  @ViewBuilder
  private var voiceOrbLayer: some View {
    if barState.isVoicePresentationActive || vm.isLingeringReply {
      NotchVoiceOrb(mode: voiceOrbMode)
        .frame(width: 72, height: voiceOrbHeight)
        .padding(.top, vm.closedNotchSize.height + voiceOrbTopGap)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
  }

  // MARK: - Closed chrome (always-visible Omi identity)

  /// The gap the icons visually straddle: the camera housing plus a small
  /// margin on a real notch, a modest fixed gap where there is no housing.
  private var cameraGap: CGFloat {
    vm.hasPhysicalNotch ? vm.cameraWidth + OmiSpacing.sm : 56
  }

  /// Ambient agent status: the mark's eight dots take the aggregate color, so a
  /// running or failed agent is visible at a glance without any surface opening.
  /// Nil (plain white) when nothing needs attention.
  private var agentStatus: AgentStatusGroup? {
    AgentStatusGroup.aggregate(for: agents.pills)
  }

  /// Logo and gear hug the camera module: [logo][camera][gear] centered as a
  /// cluster, outer space breathes. The mark opens the main Omi window; the
  /// gear opens settings — the only two interactions on the closed notch.
  private var closedChrome: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      Button(action: { MainWindowReveal.activate() }) {
        NotchOmiMark(dotColors: agentStatus.map { Array(repeating: $0.color, count: 8) } ?? [])
          .frame(width: 24, height: 24)
          // Recording dot: transcription is running.
          .overlay(alignment: .topTrailing) {
            if barState.isRecording {
              Circle()
                .fill(Color.red.opacity(0.9))
                .frame(width: 5, height: 5)
            }
          }
          .frame(
            width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height,
            alignment: .trailing
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(agentStatus?.accessibilityLabel ?? "Open Omi")
      Color.clear
        .frame(width: cameraGap)
      settingsButton
        .frame(
          width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height,
          alignment: .leading
        )
      Spacer(minLength: 0)
    }
    .frame(height: vm.closedNotchSize.height)
  }

  private var settingsButton: some View {
    Button(action: { MainWindowReveal.openSettings() }) {
      Image(systemName: "gearshape.fill")
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.7))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Omi settings")
  }

  // MARK: - Interactions

  private func handleHover(_ hovering: Bool) {
    isHovering = hovering
    // Hovering a lingering reply pauses its dismissal so the user can read it.
    if hovering {
      vm.keepReply()
    } else {
      vm.resumeReplyDismiss()
    }
  }

  /// Feeds the measured voice-content height into the view model behind a 4pt
  /// jitter filter: sub-pixel measurement noise must not drive the height
  /// animation or the measure -> resize -> remeasure loop oscillates.
  private func updateVoiceBodyHeight(_ height: CGFloat) {
    if abs((vm.voiceBodyHeight ?? 0) - height) > 4 {
      vm.voiceBodyHeight = height
    }
  }
}
