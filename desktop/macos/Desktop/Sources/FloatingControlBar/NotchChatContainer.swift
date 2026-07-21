import OmiTheme
import SwiftUI

/// Expanded notch chat container: the Chat | History segmented header plus the
/// surface it selects. Chat renders the passed live-chat content; History browses
/// past sessions. Extracted from the bar view so the header/segment logic lives in
/// one place. Voice is push-to-talk and never appears here.
struct NotchChatContainer<ChatContent: View>: View {
  @ObservedObject var state: FloatingControlBarState
  let chatProvider: ChatProvider?
  let backHelp: String
  let onBack: () -> Void
  @ViewBuilder var chatContent: () -> ChatContent

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.sm) {
        Button(action: onBack) {
          Image(systemName: "chevron.left")
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(.white.opacity(0.82))
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(backHelp)

        NotchSegmentedHeader(surface: $state.notchChatSurface)

        Spacer(minLength: 0)

        if state.notchChatSurface == .chat && state.hasVisibleConversation {
          escToClearHint
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.top, OmiSpacing.sm)

      surfaceContent
    }
  }

  @ViewBuilder
  private var surfaceContent: some View {
    switch state.notchChatSurface {
    case .chat:
      chatContent()
    case .history:
      if let chatProvider {
        NotchHistorySurface(state: state, chatProvider: chatProvider)
      } else {
        Text("No past chats yet")
          .scaledFont(size: OmiType.body)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
    }
  }

  private var escToClearHint: some View {
    HStack(spacing: OmiSpacing.xxs) {
      Text("esc")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(.secondary)
        .frame(width: 30, height: 16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(4)
      Text("to clear")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(.secondary)
    }
  }
}
