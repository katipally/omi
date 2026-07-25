import SwiftUI

/// A labelled capsule chip: an icon, a short title, and a soft hover wash.
///
/// This is the app's one "small labelled action" — the header's Settings entry,
/// the settings sidebar's Back to app, Rewind's Back. Each of those had grown
/// its own copy of the same capsule, so they drifted in height, padding, and
/// hover treatment; sharing one keeps them identical by construction.
package struct OmiChip: View {
  let icon: String
  let title: String
  var help: String?
  let action: () -> Void

  @State private var isHovering = false

  package init(
    icon: String,
    title: String,
    help: String? = nil,
    action: @escaping () -> Void
  ) {
    self.icon = icon
    self.title = title
    self.help = help
    self.action = action
  }

  package var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: icon)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .frame(width: 18, height: 18)
        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
      }
      .foregroundColor(isHovering ? OmiColors.textPrimary : OmiColors.textTertiary)
      .padding(.horizontal, OmiSpacing.md)
      .frame(height: 34)
      .background(
        Capsule(style: .continuous)
          .fill(Color.white.opacity(isHovering ? 0.10 : 0.05))
          .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
      )
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      OmiMotion.withGated(.easeOut(duration: 0.12)) { isHovering = hovering }
    }
    .help(help ?? title)
    .accessibilityLabel(help ?? title)
  }
}
