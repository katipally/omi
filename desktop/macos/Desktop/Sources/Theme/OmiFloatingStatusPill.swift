import SwiftUI

/// A small floating status capsule for work happening alongside content that is
/// already on screen. It is deliberately an overlay shape: it carries no layout
/// weight, so a background refresh cannot shift the rows underneath it.
///
/// A surface with nothing to show yet wants a centered placeholder instead —
/// this pill is for "more is coming", not "nothing is here".
package struct OmiFloatingStatusPill: View {
  let title: String

  package init(title: String) {
    self.title = title
  }

  package var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      ProgressView().controlSize(.small)
      Text(title)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textTertiary)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.xs)
    .background(
      Capsule(style: .continuous)
        .fill(Color.white.opacity(0.06))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
  }
}
