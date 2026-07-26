import AppKit

/// Lets a click anywhere off the notch put the notch away.
///
/// One instance for the whole app, owned by `NotchScreenManager`. NSEvent
/// monitors are process-wide, so installing this per panel would mean one click
/// on a two-display Mac arriving twice — and twice as many monitors to lose
/// track of. It is armed only while something on screen can actually be
/// dismissed, and disarmed by its owner on stop, hide and snooze.
///
/// Both monitors are needed and neither is enough alone: the global one sees
/// clicks in other apps, the local one sees clicks in Omi's own windows, which
/// is where a notification card most often ends up being ignored. Mouse-down
/// monitors carry no Accessibility requirement, so unlike a key monitor this is
/// never silently inert.
@MainActor
final class NotchOutsideClickDismiss {
  private let notchWindows: () -> [NSWindow]
  private let isSuppressed: () -> Bool
  private let onOutsideClick: () -> Void
  private var monitors: [Any] = []

  /// - Parameters:
  ///   - notchWindows: the panels a click has to land inside to count as a
  ///     click *on* the notch.
  ///   - isSuppressed: asked on every click, for the states where a click is
  ///     already spoken for — an open menu being the one that matters, since
  ///     its dismissing click would otherwise close the card underneath it too.
  ///   - onOutsideClick: run for a click that landed on none of them.
  init(
    notchWindows: @escaping () -> [NSWindow],
    isSuppressed: @escaping () -> Bool,
    onOutsideClick: @escaping () -> Void
  ) {
    self.notchWindows = notchWindows
    self.isSuppressed = isSuppressed
    self.onOutsideClick = onOutsideClick
  }

  var isArmed: Bool { !monitors.isEmpty }

  func arm() {
    guard monitors.isEmpty else { return }
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.handleClick()
      }
    }
    // The local monitor RETURNS the event. Swallowing it would eat every click
    // in Omi's own windows for as long as a card is on screen, which is a far
    // worse bug than a click that both dismisses the notch and lands where the
    // user aimed it — and landing where they aimed it is the intent anyway.
    let local = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.handleClick()
      }
      return event
    }
    monitors = [global, local].compactMap { $0 }
  }

  func disarm() {
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
  }

  private func handleClick() {
    guard !isSuppressed(), !isPointerOverNotch() else { return }
    onOutsideClick()
  }

  /// Hit-tests the panel's real content shape.
  ///
  /// A frame or `visibleRect` comparison is wrong here twice over: the notch is
  /// a `NotchShape`, so the corners of its bounding box are screen the notch
  /// does not occupy, and the frame is stale for the half-second a display
  /// change takes to settle. `hitTest` reads the shape the view actually claims,
  /// which is the same thing the click itself would have hit.
  private func isPointerOverNotch() -> Bool {
    let pointer = NSEvent.mouseLocation
    return notchWindows().contains { window in
      guard window.isVisible, let content = window.contentView else { return false }
      return content.hitTest(window.convertPoint(fromScreen: pointer)) != nil
    }
  }
}
