import AppKit
import Foundation

/// Holds Omi's spoken reply on the notch for a few seconds after the turn ends,
/// so a reply you only half-heard is still readable.
///
/// The text is captured *while* the response streams, not when it finishes, so
/// `isLingeringReply` is already true the instant the response goes inactive —
/// without that the surface collapses to idle for a frame before the linger
/// begins, which reads as a flicker.
///
/// Dismissal is: the hold elapsing, Esc, or a new turn starting. Hovering the
/// notch pauses the countdown and leaving it resumes on a shorter grace.
@MainActor
final class NotchReplyLingerModel: ObservableObject {
  /// The reply captured during streaming and held after the turn ends.
  @Published private(set) var heldReply: String = ""
  /// True once the linger has been dismissed (timeout, Esc, or a new turn).
  @Published private(set) var replyDismissed: Bool = false

  /// The reply is lingering when it exists and hasn't been dismissed.
  var isLingeringReply: Bool { !heldReply.isEmpty && !replyDismissed }

  private var lingerTask: Task<Void, Never>?
  private let sleep: (TimeInterval) async -> Void

  /// Injected so tests drive the countdown without wall-clock waits.
  init(
    sleep: @escaping (TimeInterval) async -> Void = { seconds in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
  ) {
    self.sleep = sleep
  }

  /// Capture the reply as it streams so the linger is ready the instant the
  /// response ends (no idle flash).
  func noteReply(_ text: String) {
    if !text.isEmpty { heldReply = text }
  }

  /// Start the dismissal countdown once the turn has ended.
  func beginReplyDismiss(hold: TimeInterval = 5) {
    guard isLingeringReply else { return }
    installEscapeMonitors()
    scheduleReplyDismiss(after: hold)
  }

  /// Pause the dismiss while the pointer is on the notch.
  func keepReply() {
    lingerTask?.cancel()
    lingerTask = nil
  }

  /// Resume the dismiss after the pointer leaves, on a shorter grace than the
  /// initial hold.
  func resumeReplyDismiss(hold: TimeInterval = 2.5) {
    guard isLingeringReply else { return }
    scheduleReplyDismiss(after: hold)
  }

  /// Dismiss the lingering reply now (Esc, or a tap that opens the app).
  func dismissReply() {
    lingerTask?.cancel()
    lingerTask = nil
    removeEscapeMonitors()
    replyDismissed = true
  }

  /// Clear all reply state for a fresh turn.
  func resetReply() {
    lingerTask?.cancel()
    lingerTask = nil
    removeEscapeMonitors()
    heldReply = ""
    replyDismissed = false
  }

  private func scheduleReplyDismiss(after hold: TimeInterval) {
    lingerTask?.cancel()
    lingerTask = Task { [weak self, sleep] in
      await sleep(hold)
      guard !Task.isCancelled else { return }
      self?.dismissReply()
    }
  }

  // MARK: - Escape

  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?

  /// The notch panel is non-activating, so a lingering reply cannot see Esc
  /// through normal key handling — the user is usually still in another app.
  /// Monitors exist only while a reply is actually lingering.
  private func installEscapeMonitors() {
    guard localEscapeMonitor == nil, globalEscapeMonitor == nil else { return }
    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isLingeringReply, event.keyCode == 53 else { return event }
      self.dismissReply()
      return nil
    }
    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isLingeringReply, event.keyCode == 53 else { return }
      self.dismissReply()
    }
  }

  private func removeEscapeMonitors() {
    if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
    if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
    localEscapeMonitor = nil
    globalEscapeMonitor = nil
  }
}
