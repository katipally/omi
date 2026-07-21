import AppKit
import OmiTheme
import SwiftUI

/// Top tab bar for the expanded notch: Chat and History, rendered as icon+label
/// pills with a sliding selection indicator. The Omi mark is the Chat tab.
/// Voice stays push-to-talk and is never a tab here. White/neutral only.
struct NotchSegmentedHeader: View {
  @Binding var surface: NotchChatSurface
  @Namespace private var tabPill

  var body: some View {
    HStack(spacing: OmiSpacing.lg) {
      tab(.chat, label: "Chat", shortcut: "1") { OmiLogoMark().frame(width: 14, height: 14) }
      tab(.history, label: "History", shortcut: "2") {
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 12, weight: .semibold))
      }
    }
    .padding(.top, 2)
  }

  @ViewBuilder
  private func tab<Icon: View>(
    _ value: NotchChatSurface,
    label: String,
    shortcut: KeyEquivalent,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    let selected = surface == value
    Button {
      guard surface != value else { return }
      OmiMotion.withGated(.spring(response: 0.34, dampingFraction: 0.82)) {
        surface = value
      }
    } label: {
      HStack(spacing: OmiSpacing.xs) {
        icon()
        Text(label)
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundColor(selected ? .white : .white.opacity(0.55))
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.xs)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .matchedGeometryEffect(id: "tabPill", in: tabPill)
        }
      }
      .scaleEffect(selected ? 1.05 : 1.0)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .keyboardShortcut(shortcut, modifiers: .command)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// The Omi wordmark, template-tinted white, loaded from the resource bundle with
/// symbol fallbacks so the tab never renders blank.
struct OmiLogoMark: View {
  var body: some View {
    if let image = Self.markImage {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .foregroundColor(.white)
    } else {
      Image(systemName: "message.fill")
        .foregroundColor(.white)
    }
  }

  private static let markImage: NSImage? = {
    for (name, ext) in [("omi_notch_logo", "svg"), ("omi_text_logo", "png")] {
      if let url = Bundle.resourceBundle.url(forResource: name, withExtension: ext),
        let image = NSImage(contentsOf: url)
      {
        image.isTemplate = true
        return image
      }
    }
    return nil
  }()
}
