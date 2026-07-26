import AppKit
import Combine
import SwiftUI

/// Per-display source of truth for one notch panel: the measured voice height
/// and every size the notch can take.
///
/// The window frame is fixed, sized to the largest any presentation can need;
/// only the inner content resizes. That is what makes every expansion visually
/// originate from the camera housing instead of a panel appearing next to it.
@MainActor
final class NotchViewModel: ObservableObject {
  @Published private(set) var closedNotchSize: CGSize
  /// Physical camera housing width (no padding) — chrome icons hug its edges.
  @Published private(set) var cameraWidth: CGFloat
  @Published private(set) var screenFrame: CGRect

  /// Measured height of the live voice content (the streaming reply). Drives
  /// the notch's grow as words wrap to new lines. Deliberately NOT part of
  /// `NotchPresentation`: it rides its own animation timeline, because keying
  /// the morph spring on a measured height makes the measure -> resize ->
  /// remeasure loop oscillate.
  @Published var voiceBodyHeight: CGFloat?

  /// Measured intrinsic height of the proactive card. Same contract as
  /// `voiceBodyHeight`: it sizes the panel but never the window, and it rides
  /// the isolated height timeline rather than the morph spring.
  @Published var notificationBodyHeight: CGFloat?
  /// Measured intrinsic height of the hint strip. Kept apart from the card's
  /// measurement even though the two surfaces are mutually exclusive: one
  /// shared value would size an incoming hint from the outgoing card until the
  /// first remeasure lands.
  @Published var hintBodyHeight: CGFloat?

  /// The reply text, captured live during streaming and held after the turn
  /// ends so the reply can linger on screen for a few seconds. Because it is
  /// already set while the response streams, `isLingeringReply` is true the
  /// instant the response goes inactive — the notch never collapses to idle for
  /// a frame before the linger begins.
  @Published var heldReply: String = ""
  /// True once the linger has been dismissed (timeout, Esc, or a new turn).
  @Published var replyDismissed: Bool = false
  /// The reply is lingering when it exists and hasn't been dismissed.
  var isLingeringReply: Bool { !heldReply.isEmpty && !replyDismissed }
  private var lingerTask: Task<Void, Never>?

  let displayID: CGDirectDisplayID

  private weak var window: NSWindow?

  /// Injected so the linger timings are testable without wall-clock sleeps.
  private let sleep: (TimeInterval) async -> Void

  init(
    displayID: CGDirectDisplayID,
    screenFrame: CGRect,
    closedNotchSize: CGSize,
    cameraWidth: CGFloat = NotchMetrics.fallbackHiddenCenterWidth,
    sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
  ) {
    self.sleep = sleep
    self.displayID = displayID
    self.screenFrame = screenFrame
    self.closedNotchSize = closedNotchSize
    self.cameraWidth = cameraWidth
  }

  convenience init(
    screen: NSScreen,
    sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
  ) {
    self.init(
      displayID: screen.omiDisplayID,
      screenFrame: screen.frame,
      closedNotchSize: NotchMetrics.closedSize(for: screen),
      cameraWidth: NotchMetrics.cameraWidth(for: screen),
      sleep: sleep
    )
  }

  // MARK: - Sizing

  /// Fixed width for the expanded voice states (listening / responding); only
  /// the HEIGHT grows with the measured content, so the island grows downward
  /// out of the notch as the answer streams — the Dynamic Island grow, not a
  /// wide pop. Restrained, but never narrower than the camera module.
  var voiceWidth: CGFloat {
    max(closedNotchSize.width, clampValue(screenFrame.width * 0.2, 280, 340))
  }
  var voiceMinHeight: CGFloat { clampValue(closedNotchSize.height + 82, 120, 168) }
  /// Voice is verbal — the panel shouldn't dominate the screen. Cap at 40% of
  /// the display height; longer replies scroll inside it.
  var voiceMaxHeight: CGFloat { screenFrame.height * 0.4 }

  var voiceExpandedSize: CGSize {
    let height = voiceBodyHeight.map { clampValue($0, voiceMinHeight, voiceMaxHeight) } ?? voiceMinHeight
    return CGSize(width: voiceWidth, height: height)
  }

  /// The compact pill between listening and responding: camera strip plus the
  /// orb (now the rotating ring), centered, no text. Narrower than the expanded
  /// voice width so the island visibly contracts into "thinking".
  var thinkingSize: CGSize {
    CGSize(width: closedNotchSize.width, height: closedNotchSize.height + 42)
  }

  var hintWidth: CGFloat {
    clampValue(closedNotchSize.width + NotchMetrics.hintExtraWidth, 280, 380)
  }

  /// The strip follows its text the way the voice body follows the reply: a
  /// one-line hint gets one line of chrome, a wrapped one grows to hold it.
  /// Unmeasured falls back to the floor, so the strip opens at its resting
  /// height and grows — never opens tall and snaps down.
  var hintSize: CGSize {
    let row =
      hintBodyHeight.map { clampValue($0, NotchMetrics.hintRowHeight, NotchMetrics.hintMaxHeight) }
      ?? NotchMetrics.hintRowHeight
    return CGSize(width: hintWidth, height: closedNotchSize.height + row)
  }

  var notificationWidth: CGFloat {
    max(closedNotchSize.width, NotchMetrics.notificationWidth)
  }

  /// The panel is exactly as tall as the card inside it. A fixed card height is
  /// what left a short notification sitting in dead black and clipped a long
  /// one, so the height comes from the card's own intrinsic measurement.
  var notificationSize: CGSize {
    let card =
      notificationBodyHeight.map {
        clampValue($0, NotchMetrics.notificationMinHeight, NotchMetrics.notificationMaxHeight)
      } ?? NotchMetrics.notificationMinHeight
    return CGSize(
      width: notificationWidth,
      height: closedNotchSize.height + NotchMetrics.notificationSpacing + card)
  }

  /// The panel size for a presentation — the single sizing authority. Content
  /// (in NotchView) switches on the same value, so size and content stay locked.
  func size(for presentation: NotchPresentation) -> CGSize {
    switch presentation {
    case .listening, .responding: return voiceExpandedSize
    case .thinking: return thinkingSize
    case .hint: return hintSize
    case .notification: return notificationSize
    case .idle: return closedNotchSize
    }
  }

  /// The tallest the passive surfaces can ever be. These are what the window is
  /// sized from — deliberately the ceilings, never the measured values. Feeding
  /// a measurement into the window frame would resize the NSPanel itself as a
  /// card grew, and the expansion would stop looking like it came out of the
  /// camera housing.
  private var notificationMaxPanelHeight: CGFloat {
    closedNotchSize.height + NotchMetrics.notificationSpacing + NotchMetrics.notificationMaxHeight
  }

  private var hintMaxPanelHeight: CGFloat {
    closedNotchSize.height + NotchMetrics.hintMaxHeight
  }

  /// The window is fixed at the largest any presentation can ever need; only
  /// the inner content scales, so expansion always originates from the notch.
  private var maxContentSize: CGSize {
    CGSize(
      width: max(notificationWidth, max(hintWidth, voiceWidth)),
      height: max(notificationMaxPanelHeight, max(hintMaxPanelHeight, voiceMaxHeight))
    )
  }

  var windowSize: CGSize {
    CGSize(
      width: maxContentSize.width + NotchMetrics.shadowPadding * 2,
      height: maxContentSize.height + NotchMetrics.shadowPadding * 2 + NotchMetrics.topOverscan
    )
  }

  /// The visible black region in screen coordinates for a presentation — the
  /// window itself is larger, so hit-testing has to use this, not the frame.
  func visibleRect(for presentation: NotchPresentation) -> CGRect {
    let size = size(for: presentation)
    return CGRect(
      x: screenFrame.midX - size.width / 2,
      y: screenFrame.maxY - size.height,
      width: size.width,
      height: size.height
    )
  }

  // MARK: - Window coordination

  func attach(window: NSWindow) {
    self.window = window
    positionWindow()
  }

  func refresh(for screen: NSScreen) {
    screenFrame = screen.frame
    closedNotchSize = NotchMetrics.closedSize(for: screen)
    cameraWidth = NotchMetrics.cameraWidth(for: screen)
    positionWindow()
  }

  /// Fixed geometry: centered horizontally, pinned to the top. Never animated.
  /// The panel's top edge sits `topOverscan` *above* the display so the notch
  /// bleeds off-screen rather than trying to land exactly on the top pixel row.
  private func positionWindow() {
    guard let window else { return }
    let size = windowSize
    let origin = NSPoint(
      x: screenFrame.midX - size.width / 2,
      y: screenFrame.maxY - size.height + NotchMetrics.topOverscan
    )
    window.setFrame(NSRect(origin: origin, size: size), display: true)
  }

  // MARK: - Response linger (hold the reply briefly after the turn ends)

  /// Capture the reply as it streams so the linger is ready the instant the
  /// response ends (no idle flash).
  func noteReply(_ text: String) {
    if !text.isEmpty { heldReply = text }
  }

  /// The ceiling on a linger the pointer is holding open. Generous on purpose:
  /// anything short would yank a long reply away from someone still reading it,
  /// and the only thing this has to prevent is a reply that never leaves.
  static let heldReplyMaxHold: TimeInterval = 30

  /// Whether the pointer is resting on the panel. Both directions of the
  /// dismissal read it — a linger that begins under the pointer takes the
  /// ceiling instead of the short hold, and a pointer arriving mid-linger
  /// replaces the countdown with the ceiling instead of cancelling it — so a
  /// resume that never arrives cannot strand the reply on screen.
  private var isPointerHolding = false

  /// Start the dismissal countdown once the turn has ended.
  func beginReplyDismiss(hold: TimeInterval = 5) {
    guard isLingeringReply else { return }
    scheduleReplyDismiss(after: isPointerHolding ? Self.heldReplyMaxHold : hold)
  }

  /// Hold the reply while the pointer is on the notch, bounded by the ceiling.
  func keepReply() {
    isPointerHolding = true
    guard isLingeringReply else { return }
    scheduleReplyDismiss(after: Self.heldReplyMaxHold)
  }

  /// Resume the dismiss after the pointer leaves, on a shorter grace than the
  /// initial hold — the reply has already had its read time.
  func resumeReplyDismiss(hold: TimeInterval = 2.5) {
    isPointerHolding = false
    guard isLingeringReply else { return }
    scheduleReplyDismiss(after: hold)
  }

  /// Dismiss the lingering reply now (Esc).
  func dismissReply() {
    lingerTask?.cancel()
    replyDismissed = true
  }

  /// Clear all reply state for a fresh turn.
  func resetReply() {
    lingerTask?.cancel()
    lingerTask = nil
    heldReply = ""
    replyDismissed = false
    voiceBodyHeight = nil
  }

  private func scheduleReplyDismiss(after hold: TimeInterval) {
    lingerTask?.cancel()
    lingerTask = Task { [weak self, sleep] in
      await sleep(hold)
      guard !Task.isCancelled else { return }
      self?.replyDismissed = true
    }
  }

  deinit {
    lingerTask?.cancel()
  }
}

private func clampValue(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
  min(max(value, low), high)
}
