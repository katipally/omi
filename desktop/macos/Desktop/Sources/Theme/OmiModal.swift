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
  /// The modal's height: its content, capped.
  ///
  /// Unmeasured content resolves to 0 rather than "unconstrained", and that is
  /// load-bearing. These sheets contain their own greedy `ScrollView`; leave the
  /// frame unconstrained for even one layout pass and the scroll view swallows
  /// the whole proposal, reports *that* back as the content height, and the
  /// modal pins to `maxHeight` with the content stranded in dead space. A zero
  /// height collapses it instead, so the first real measurement is the content's
  /// own.
  package static func height(contentHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
    min(max(0, contentHeight), maxHeight)
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
    // The measurement has to happen inside a scroll view. Every sheet using this
    // brings its own `ScrollView`, which is greedy: measured against a bounded
    // proposal it reports the proposal back, so the modal pins to `maxHeight`
    // and short content sits in dead space. Inside a scroll view the proposal is
    // unbounded, so the sheet reports the height it actually wants.
    ScrollView {
      content
        .frame(width: width)
        .background(
          GeometryReader { geo in
            Color.clear.preference(key: ModalContentHeightKey.self, value: geo.size.height)
          }
        )
    }
    .frame(
      width: width,
      height: FittedModalGeometry.height(contentHeight: contentHeight, maxHeight: maxHeight)
    )
    // Only this outer scroll view moves, and only once the content is capped;
    // below the cap the modal is exactly content-sized and there is nothing to
    // scroll.
    .scrollDisabled(!FittedModalGeometry.isCapped(contentHeight: contentHeight, maxHeight: maxHeight))
    .scrollBounceBehavior(.basedOnSize)
    .onPreferenceChange(ModalContentHeightKey.self) { contentHeight = $0 }
  }
}

extension View {
  package func fittedModal(width: CGFloat, maxHeight: CGFloat) -> some View {
    modifier(FittedModal(width: width, maxHeight: maxHeight))
  }
}
