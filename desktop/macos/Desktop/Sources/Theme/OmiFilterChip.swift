import SwiftUI

/// The label content for a header filter control: an icon, a title, and an
/// optional disclosure chevron, emphasized when the filter is narrowing results.
///
/// This is a label rather than a button so it can sit inside a `Button`, a
/// `Menu`, or a popover anchor without dictating how the control is driven.
package struct OmiFilterChip: View {
  let icon: String?
  let title: String
  let isActive: Bool
  var showsDisclosure: Bool
  /// Tint for the leading glyph only. Defaults to the label colour.
  var iconColor: Color?

  package init(
    icon: String?,
    title: String,
    isActive: Bool = false,
    showsDisclosure: Bool = false,
    iconColor: Color? = nil
  ) {
    self.icon = icon
    self.title = title
    self.isActive = isActive
    self.showsDisclosure = showsDisclosure
    self.iconColor = iconColor
  }

  package var body: some View {
    HStack(spacing: OmiSpacing.xs) {
      if let icon {
        Image(systemName: icon)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(iconColor)
      }
      Text(title)
        .scaledFont(size: OmiType.body, weight: isActive ? .medium : .regular)
        .lineLimit(1)
      if showsDisclosure {
        Image(systemName: "chevron.down")
          .scaledFont(size: OmiType.micro, weight: .semibold)
          .foregroundColor(OmiColors.textTertiary)
      }
    }
    .foregroundColor(isActive ? OmiColors.textPrimary : OmiColors.textSecondary)
    .omiHeaderControlChrome(isActive: isActive)
  }
}

extension View {
  /// Height, padding, and capsule for anything that sits in a page header row
  /// beside the search field. Sharing it is what keeps a row of mixed controls
  /// on one baseline — they had drifted to four different heights.
  package func omiHeaderControlChrome(isActive: Bool = false) -> some View {
    self
      .padding(.horizontal, OmiSpacing.md)
      .frame(height: OmiChrome.controlHeight)
      .background(
        Capsule(style: .continuous)
          .fill(Color.white.opacity(isActive ? 0.10 : 0.06))
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color.white.opacity(isActive ? 0.22 : 0.08), lineWidth: 1)
          )
      )
      .contentShape(Capsule(style: .continuous))
      .omiAnimation(.easeOut(duration: 0.15), value: isActive)
  }
}
