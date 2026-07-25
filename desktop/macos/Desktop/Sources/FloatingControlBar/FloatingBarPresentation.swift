import Foundation

/// Shared reveal implementation for persistent settings, temporary snoozes,
/// and direct Push-to-Talk presentation.
extension FloatingControlBarManager {
  /// Applies the saved launch preference without overriding a temporary
  /// notification snooze. Push-to-Talk and Settings call `show()` instead.
  func showForLaunch() {
    present(.background, persistEnabledPreference: false)
  }

  func present(
    _ request: FloatingBarPresentationRequest,
    persistEnabledPreference: Bool
  ) {
    if persistEnabledPreference {
      isEnabled = true
    }
    guard FloatingBarPresentationPolicy.shouldPresent(request: request, isSnoozed: isSnoozed) else {
      return
    }
    hasRevealedNotchThisSession = true
    notch.showAll()
    log("FloatingControlBarManager: presented notch panels (request=\(request))")
  }
}
