import AppKit
import OmiTheme
import SwiftUI

/// Chat | History segmented control for the expanded notch header. The Omi mark
/// is the Chat segment; History browses past sessions. Voice stays push-to-talk
/// and is never a segment here. White/neutral only (INV-UI-1).
struct NotchSegmentedHeader: View {
  @Binding var surface: NotchChatSurface
  @Namespace private var pill

  var body: some View {
    HStack(spacing: OmiSpacing.xxs) {
      segment(.chat) {
        HStack(spacing: OmiSpacing.xs) {
          OmiLogoMark()
            .frame(width: 15, height: 15)
          Text("Chat")
        }
      }
      segment(.history) {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "clock.arrow.circlepath")
            .scaledFont(size: OmiType.caption, weight: .semibold)
          Text("History")
        }
      }
    }
    .padding(OmiSpacing.hairline)
    .background(Color.white.opacity(0.06))
    .clipShape(Capsule())
  }

  @ViewBuilder
  private func segment<Label: View>(_ value: NotchChatSurface, @ViewBuilder label: () -> Label) -> some View {
    let selected = surface == value
    Button {
      guard surface != value else { return }
      OmiMotion.withGated(.spring(response: 0.32, dampingFraction: 0.82)) {
        surface = value
      }
    } label: {
      label()
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundColor(selected ? .white : .white.opacity(0.55))
        .padding(.horizontal, OmiSpacing.sm)
        .padding(.vertical, OmiSpacing.xs)
        .background {
          if selected {
            Capsule()
              .fill(Color.white.opacity(0.12))
              .matchedGeometryEffect(id: "pill", in: pill)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(value == .chat ? "Chat" : "History")
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
      Image(systemName: "bubble.left.and.bubble.right.fill")
        .foregroundColor(.white)
    }
  }

  private static let markImage: NSImage? = {
    for name in ["omi_notch_logo", "omi_text_logo"] {
      let ext = name.hasSuffix("logo") && name.contains("notch") ? "svg" : "png"
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
