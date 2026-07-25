import SwiftUI

/// The title-and-subtitle block that opens a full-width list page.
package struct OmiPageHeader: View {
  let title: String
  let subtitle: String?

  package init(title: String, subtitle: String? = nil) {
    self.title = title
    self.subtitle = subtitle
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundStyle(OmiColors.textPrimary)
      if let subtitle {
        Text(subtitle)
          .scaledFont(size: OmiType.caption)
          .foregroundStyle(OmiColors.textTertiary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
