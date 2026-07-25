import AppKit
import SwiftUI

/// The per-display notch panel. Non-activating so opening/typing never
/// surfaces the main window or deactivates the user's frontmost app; the
/// window frame is fixed (sized by NotchViewModel) and never animates.
final class NotchWindow: NSPanel {
  /// The bar must never be buried under third-party overlay apps: notch
  /// companions (e.g. Clicky) park windows at .popUpMenu (101) and full-screen
  /// overlays at .screenSaver (1000), so .statusBar (25) lost the notch to
  /// them. Assistive-tech-high (1500) beats every common overlay level while
  /// staying below the system cursor and the screen-lock shield. It also
  /// covers the menu-bar strip, which the notch body must do.
  static let normalLevel = NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow))
  )

  /// In-process NSMenus (context menus, pickers) render at .popUpMenu (101);
  /// while one is tracking, the panel drops to that level so the notch cannot
  /// occlude its own menus. Depth-counted because nested submenus emit their
  /// own begin/end tracking notifications.
  private var menuTrackingDepth = 0
  /// Notification tokens live in their own bag so removal can happen from the
  /// bag's nonisolated deinit when the window deallocates.
  private final class ObserverBag: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
  }
  private let menuTrackingObservers = ObserverBag()
  /// While a system permission/auth dialog is frontmost, drop below it so the
  /// user can actually see and answer it — at 1500 the notch would otherwise
  /// cover TCC prompts.
  private var yieldsToSystemDialog = false

  override init(
    contentRect: NSRect,
    styleMask: NSWindow.StyleMask,
    backing: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

    isFloatingPanel = true
    isOpaque = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    backgroundColor = .clear
    isMovable = false
    hasShadow = false
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    appearance = NSAppearance(named: .vibrantDark)
    level = Self.normalLevel
    collectionBehavior = [
      .fullScreenAuxiliary,
      .stationary,
      .canJoinAllSpaces,
      .ignoresCycle,
    ]
    registerMenuTrackingObservers()
  }

  func setYieldsToSystemDialog(_ yields: Bool) {
    yieldsToSystemDialog = yields
    applySurfaceLevel()
  }

  private func applySurfaceLevel() {
    if menuTrackingDepth > 0 {
      level = .popUpMenu
    } else if yieldsToSystemDialog {
      level = .floating
    } else {
      level = Self.normalLevel
    }
  }

  private func registerMenuTrackingObservers() {
    let center = NotificationCenter.default
    menuTrackingObservers.tokens.append(
      center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.menuTrackingDepth += 1
          self.applySurfaceLevel()
        }
      })
    menuTrackingObservers.tokens.append(
      center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
          self.applySurfaceLevel()
        }
      })
  }

  /// The notch never takes the keyboard. It has no text input — typing lives in
  /// the main app — and stealing key focus from whatever the user is working in
  /// would be a bug, not a feature. Esc for a lingering reply is handled by
  /// event monitors in `NotchView`, which run without the panel being key.
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// The panel is never key, so views must accept the first mouse click or taps
/// get swallowed by window activation.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
