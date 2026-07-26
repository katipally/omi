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
  @Environment(\.sbTheme) private var sb

  @State private var isHovering = false
  /// Esc key monitors, live only while a reply lingers (zero idle cost).
  @State private var lingerEscMonitors: [Any] = []

  // MARK: - Presentation ladder

  /// Whether this panel owns the current voice turn. A nil latch means no turn
  /// has started yet, so every panel behaves as it always did.
  private var isVoiceDisplay: Bool {
    barState.voiceDisplayID.map { $0 == vm.displayID } ?? true
  }

  /// The status line the ladder derives from: the reducer's PTT banner, falling
  /// back to the one-shot transient hint for states the reducer does not own.
  private var hintText: String {
    barState.pttHintText.isEmpty ? barState.transientHintText : barState.pttHintText
  }

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
      hintText: hintText,
      notificationID: barState.currentNotification?.id,
      isVoiceDisplay: isVoiceDisplay
    )
    // A finished reply lingers for a few seconds after the turn ends. heldReply
    // is set while the response streams, so this is already true the instant
    // the response goes inactive — the notch never collapses to idle first.
    // Gated on the same display, or the reply would linger on every screen.
    if vm.isLingeringReply, isVoiceDisplay {
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
      // The panel starts above the display, so shift the whole surface down by
      // that much: the shape's top edge then lands exactly on the physical top
      // edge and only the bleed band is off-screen.
      .padding(.top, NotchMetrics.topOverscan)
      .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
      // A panel overlapping the menu bar picks up a top safe-area inset, which
      // would push the notch down off the edge it has to be welded to.
      .ignoresSafeArea()
      // Capture the reply as it streams so the linger is ready the moment the
      // response ends (prevents a one-frame collapse to idle).
      .onChange(of: barState.liveVoiceAssistantText) { _, reply in
        guard isVoiceDisplay else { return }
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
      // A measurement is dropped when its surface leaves, not when its content
      // changes. Two cards in a row animate from one measured height to the
      // next; a card arriving after an empty stretch has to open at the resting
      // height and grow, or it opens at the previous card's height and corrects
      // on the following frame, which reads as a flinch.
      .onChange(of: barState.currentNotification?.id) { _, id in
        if id == nil { vm.notificationBodyHeight = nil }
      }
      .onChange(of: hintText.isEmpty) { _, empty in
        if empty { vm.hintBodyHeight = nil }
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
        // The bleed band above the display's top edge. The shape's top edge is
        // full width, so this butts against it exactly; everything it covers is
        // off-screen, which is the point — the visible top row is always black.
        .overlay(alignment: .top) {
          Rectangle()
            .fill(.black)
            .frame(height: NotchMetrics.topOverscan)
            .offset(y: -NotchMetrics.topOverscan)
        }
        .shadow(
          color: (isHovering || presentation.isExpandedSurface) ? .black.opacity(0.7) : .clear,
          radius: 8
        )
      bodyContent
        .frame(width: displayedSize.width, height: displayedSize.height, alignment: .top)
        .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
      // Chrome and mark are their own persistent layers, never part of the
      // content crossfade. The gear holds its lobe through every presentation,
      // and the mark travels between that chrome and the orb slot instead of
      // one logo fading out while a second fades in.
      closedChrome
        .frame(width: displayedSize.width)
      omiMarkLayer
    }
    .animation(morphAnimation, value: presentation)
    .animation(heightAnimation, value: vm.voiceBodyHeight)
    .animation(heightAnimation, value: vm.notificationBodyHeight)
    .animation(heightAnimation, value: vm.hintBodyHeight)
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
      // Spacing lives in the strip's own padding rather than the stack, so the
      // measured value is the whole strip and the panel height is exactly
      // `closed chrome + measured strip` with nothing unaccounted for.
      VStack(spacing: 0) {
        chromeReserve
        Text(text)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundStyle(sb.pillInk(.w75))
          .multilineTextAlignment(.center)
          .lineLimit(hintLineLimit)
          .truncationMode(.tail)
          .padding(.horizontal, OmiSpacing.md)
          .padding(.top, OmiSpacing.hairline)
          .padding(.bottom, OmiSpacing.sm)
          .frame(maxWidth: .infinity)
          .measuredIntrinsicHeight(updateHintBodyHeight)
      }
      .transition(contentTransition)
    case .notification(let id):
      VStack(spacing: NotchMetrics.notificationSpacing) {
        chromeReserve
        if let notification = barState.currentNotification, notification.id == id {
          NotchNotificationCard(notification: notification)
            .measuredIntrinsicHeight(updateNotificationBodyHeight)
        }
      }
      .transition(contentTransition)
    case .idle:
      // The chrome is its own layer; idle is the black bar and nothing else.
      Color.clear
    }
  }

  /// Vertical space the persistent chrome layer occupies at the top.
  private var chromeReserve: some View {
    Color.clear.frame(height: vm.closedNotchSize.height)
  }

  /// A hint is a status line, not a paragraph. Two lines holds every string the
  /// reducer produces even at the largest type sizes; anything longer truncates
  /// rather than growing the notch into a panel.
  private var hintLineLimit: Int { 2 }

  // MARK: - The Omi mark (one instance for the panel's whole life)

  /// Height reserved for the morphing orb below the camera housing.
  private var voiceOrbHeight: CGFloat { 30 }
  private var voiceOrbTopGap: CGFloat { 4 }
  /// Side of the mark while it sits in the chrome lobe.
  private var chromeMarkSize: CGFloat { 24 }
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
    guard isVoiceDisplay else { return .logo }
    if barState.isListeningPhase { return .listening }
    if barState.isThinking { return .thinking }
    if barState.isVoiceResponseActive { return .speaking }
    return .logo  // at rest: the chrome mark, or a finished reply lingering
  }

  /// Where the mark lives for a presentation. Home is the left chrome lobe;
  /// a voice turn takes it to the orb slot below the camera housing. Both are
  /// measured from the ZStack's top-center, so the two positions interpolate
  /// on the morph spring and the mark arrives exactly as the black mass
  /// finishes growing.
  private var markFrame: (size: CGSize, offset: CGSize) {
    if presentation.isVoiceTurn {
      return (
        CGSize(width: 72, height: voiceOrbHeight),
        CGSize(width: 0, height: vm.closedNotchSize.height + voiceOrbTopGap)
      )
    }
    return (
      CGSize(width: chromeMarkSize, height: chromeMarkSize),
      CGSize(
        width: -(cameraGap / 2 + NotchMetrics.closedSideWidth / 2),
        height: (vm.closedNotchSize.height - chromeMarkSize) / 2
      )
    )
  }

  private var omiMarkLayer: some View {
    NotchVoiceOrb(
      mode: voiceOrbMode,
      // Status tint belongs to the resting mark; during a turn the waveform is
      // reporting live audio and must not be recolored by a background job.
      dotColors: presentation.isVoiceTurn
        ? [] : agentStatus.map { Array(repeating: $0.color, count: 8) } ?? []
    )
    .frame(width: markFrame.size.width, height: markFrame.size.height)
    // Recording dot: transcription is running. Only while the mark is home —
    // during a turn the waveform already shows that audio is live.
    .overlay(alignment: .topTrailing) {
      if barState.isRecording, !presentation.isVoiceTurn {
        Circle()
          .fill(OmiColors.error.opacity(0.9))
          .frame(width: 5, height: 5)
      }
    }
    .offset(x: markFrame.offset.width, y: markFrame.offset.height)
    .allowsHitTesting(false)
  }

  // MARK: - Closed chrome (always-visible Omi identity)

  /// The gap the icons visually straddle: the camera housing plus a small
  /// margin. Synthesized where there is no housing (`NotchMetrics.cameraWidth`
  /// falls back), so the chrome sits at the same offsets on every display.
  private var cameraGap: CGFloat {
    vm.cameraWidth + OmiSpacing.sm
  }

  /// Ambient agent status: the mark's eight dots take the aggregate color, so a
  /// running or failed agent is visible at a glance without any surface opening.
  /// Nil (plain white) when nothing needs attention.
  private var agentStatus: AgentStatusGroup? {
    AgentStatusGroup.aggregate(for: agents.pills)
  }

  /// The two lobes flanking the camera module: [mark][camera][gear], centered
  /// as a cluster so it stays put as the panel widens. Both lobes are the same
  /// width with their content centered, so the cluster is optically symmetric
  /// about the housing — edge-aligning instead puts the 24pt mark and the 11pt
  /// gear at different distances from it.
  ///
  /// The left lobe is only the mark's *hit target*: the mark itself is drawn by
  /// `omiMarkLayer`, which has to be free to travel out of this row. Tapping it
  /// opens the main Omi window; the gear opens settings.
  private var closedChrome: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      Button(action: { MainWindowReveal.activate() }) {
        Color.clear
          .frame(width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // Only while the mark is actually here. During a turn the lobe is empty,
      // and an invisible button is worse than no button — the reply itself is
      // the tap target then.
      .disabled(presentation.isVoiceTurn)
      .accessibilityHidden(presentation.isVoiceTurn)
      .accessibilityLabel(agentStatus?.accessibilityLabel ?? "Open Omi")
      Color.clear
        .frame(width: cameraGap)
      settingsButton
        .frame(width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height)
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

  // MARK: - Measurement

  /// Sub-pixel measurement noise must not drive the height animation: a
  /// remeasure within this tolerance is treated as the same height, which is
  /// what keeps the measure -> resize -> remeasure loop from oscillating. Below
  /// a line of the smallest type, so nothing a reader can see is filtered out.
  private static let heightJitterTolerance: CGFloat = 4

  /// Whether a fresh measurement is far enough from the one in hand to be worth
  /// re-sizing for. Every measured surface asks this, so they cannot drift to
  /// different tolerances.
  private func exceedsJitter(_ measured: CGFloat, _ current: CGFloat?) -> Bool {
    abs((current ?? 0) - measured) > Self.heightJitterTolerance
  }

  private func updateVoiceBodyHeight(_ height: CGFloat) {
    if exceedsJitter(height, vm.voiceBodyHeight) { vm.voiceBodyHeight = height }
  }

  private func updateNotificationBodyHeight(_ height: CGFloat) {
    if exceedsJitter(height, vm.notificationBodyHeight) { vm.notificationBodyHeight = height }
  }

  private func updateHintBodyHeight(_ height: CGFloat) {
    if exceedsJitter(height, vm.hintBodyHeight) { vm.hintBodyHeight = height }
  }
}

extension View {
  /// Reports this view's INTRINSIC height.
  ///
  /// `fixedSize` is the load-bearing half. The notch's content sits inside a
  /// frame that the measurement itself determines, so measuring the container
  /// would hand the panel's current height straight back and the
  /// measure -> resize -> remeasure loop would feed on itself. Pinned to its
  /// own ideal height, the view reports what its content actually needs.
  fileprivate func measuredIntrinsicHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
    fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        report($0)
      }
  }
}
