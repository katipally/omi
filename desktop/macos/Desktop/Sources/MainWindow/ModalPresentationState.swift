import SwiftUI

/// Hoists a page's modal up to the shell so the WHOLE window (top bar included)
/// gets one uniform frosted backdrop, and the modal card renders sharp on top.
/// Pages keep their own selection state and mirror it here via `dismissableSheet`.
///
/// Hoisting moves the modal's accessibility contract to the shell as well: the
/// backdrop owner is responsible for hiding the content behind it and marking
/// the card modal. See `DesktopHomeView.mainContent`.
@MainActor final class ModalPresentationState: ObservableObject {
  static let shared = ModalPresentationState()

  @Published private(set) var content: AnyView?
  private var token: UUID?
  private var onDismiss: () -> Void = {}

  var isPresenting: Bool { content != nil }

  func present<V: View>(token: UUID, dismiss: @escaping () -> Void, @ViewBuilder content: () -> V) {
    self.token = token
    self.onDismiss = dismiss
    self.content = AnyView(content())
  }

  /// Clears only if `token` owns the current presentation, so a page tearing
  /// down cannot blank a modal another page has since put up.
  func clear(token: UUID) {
    guard self.token == token else { return }
    content = nil
    self.token = nil
    onDismiss = {}
  }

  /// Called by the shell backdrop (tap-outside / Escape) to dismiss.
  func dismiss() { onDismiss() }
}
