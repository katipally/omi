import AppKit
import SwiftUI

/// Reveals the conversation when the user scrolls on the hub — the transcript
/// conceptually lives "above" the hub, and scrolling up is how you reach it.
///
/// This taps an app-global event stream, so ownership matters more than the
/// gesture. `start` and `stop` are both idempotent and two owners call `stop`
/// (the hub's `onDisappear` and the page's), because a monitor that outlives
/// the hub would fire on every scroll anywhere in the app. Cleanup is explicit
/// rather than in `deinit`: Swift 6 forbids touching the non-Sendable monitor
/// token from a nonisolated deinit. The predicate is re-evaluated per event so
/// a scroll can never reveal from another surface or from under a modal.
@MainActor
final class HomeChatRevealMonitor: ObservableObject {
  private var monitor: Any?

  /// Minimum vertical delta that counts as deliberate, so trackpad jitter and
  /// horizontal swipes don't leave the hub by accident.
  static let minimumScrollDelta: CGFloat = 4

  static func isDeliberateScroll(deltaY: CGFloat) -> Bool {
    abs(deltaY) > minimumScrollDelta
  }

  var isRunning: Bool { monitor != nil }

  /// Installs the monitor if it isn't already running. `shouldReveal` gates on
  /// current state; `onReveal` runs at most once per qualifying scroll.
  func start(shouldReveal: @escaping () -> Bool, onReveal: @escaping () -> Void) {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      if shouldReveal(), Self.isDeliberateScroll(deltaY: event.scrollingDeltaY) {
        onReveal()
      }
      return event
    }
  }

  func stop() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }
}
