import SwiftUI

/// The floating composer pill below the notch body. Reuses the main window's
/// ChatInputView bound to the same provider (one draft, one timeline); the
/// glass chrome is Liquid Glass on macOS 26+, HUD blur below.
struct NotchTrayView: View {
  @ObservedObject var chatProvider: ChatProvider

  var body: some View {
    ChatInputView(
      onSend: { text in
        AnalyticsManager.shared.chatMessageSent(
          messageLength: text.count, hasSelectedAppContext: false, source: "notch_chat")
        Task { await chatProvider.sendMainDraft(text) }
      },
      onStop: { chatProvider.stopAgent(owner: .mainChat) },
      isSending: chatProvider.isSending,
      isStopping: chatProvider.isStopping,
      placeholder: "Ask Omi...",
      mode: $chatProvider.chatMode,
      inputText: $chatProvider.draftText,
      attachments: $chatProvider.pendingAttachments,
      onAttachmentsAdded: { urls in
        chatProvider.addAttachments(urls.compactMap { ChatAttachment.from(url: $0) })
      },
      onAttachmentRemoved: { id in
        chatProvider.removePendingAttachment(id: id)
      }
    )
    .padding(6)
    .background(trayGlass)
  }

  @ViewBuilder
  private var trayGlass: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    if #available(macOS 26.0, *) {
      shape.fill(.clear).glassEffect(.regular, in: shape)
    } else {
      shape
        .fill(Color.black.opacity(0.35))
        .background(
          VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, alphaValue: 1).clipShape(shape)
        )
        .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
  }
}
