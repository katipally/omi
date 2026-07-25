import SwiftUI

private struct ModalContentHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// How a fitted modal resolves its height, split out so the unmeasured first
/// frame and the scroll handoff are checkable without driving a real window.
package enum FittedModalGeometry {
  /// `nil` means "don't constrain yet" — the modal sizes naturally until its
  /// content reports a height.
  ///
  /// Pinning the unmeasured frame to `maxHeight` instead looks reasonable but
  /// fails open: sheets here wrap their own `ScrollView`, and a scroll view is
  /// greedy, so if the measurement never propagates the modal stays stuck at
  /// full height with dead space above and below the content. Natural sizing
  /// degrades to the right answer instead of the tallest one.
  package static func height(contentHeight: CGFloat, maxHeight: CGFloat) -> CGFloat? {
    guard contentHeight > 0 else { return nil }
    return min(contentHeight, maxHeight)
  }

  /// Whether the content is tall enough to be capped. The sheets scroll
  /// themselves; this only reports that the cap is doing something.
  package static func isCapped(contentHeight: CGFloat, maxHeight: CGFloat) -> Bool {
    contentHeight > maxHeight
  }
}

/// Sizes a modal to its content: fixed width, height fits the content up to
/// `maxHeight`, and anything taller scrolls. No dead space under short content,
/// no overflow for long content.
struct FittedModal: ViewModifier {
  let width: CGFloat
  let maxHeight: CGFloat

  @State private var contentHeight: CGFloat = 0

  func body(content: Content) -> some View {
    // The measurement rides on the content itself rather than inside a wrapping
    // scroll view: these sheets bring their own `ScrollView`, and measuring
    // through it would report the proposal back to itself instead of the
    // content's real height.
    content
      .frame(width: width)
      .background(
        GeometryReader { geo in
          Color.clear.preference(key: ModalContentHeightKey.self, value: geo.size.height)
        }
      )
      .frame(
        width: width,
        height: FittedModalGeometry.height(contentHeight: contentHeight, maxHeight: maxHeight)
      )
      .frame(maxHeight: maxHeight)
      .onPreferenceChange(ModalContentHeightKey.self) { contentHeight = $0 }
  }
}

extension View {
  package func fittedModal(width: CGFloat, maxHeight: CGFloat) -> some View {
    modifier(FittedModal(width: width, maxHeight: maxHeight))
  }
}
