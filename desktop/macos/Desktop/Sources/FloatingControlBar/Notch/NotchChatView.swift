import SwiftUI

/// The chat tab: the SAME timeline as the main chat window, rendered by the
/// shared ChatMessagesView over ChatProvider.mainInstance (INV-6: the notch is
/// an I/O device over the one kernel transcript, never a second store). Also
/// owns the height measure loop that lets the panel grow to fit the answer.
struct NotchChatView: View {
  @ObservedObject var chatProvider: ChatProvider
  /// Reports the transcript's measured content height; NotchView filters
  /// sub-4pt jitter before writing it into the view model.
  let onBodyHeightChange: (CGFloat) -> Void

  var body: some View {
    ChatMessagesView(
      messages: chatProvider.messages,
      isSending: chatProvider.isSending,
      hasMoreMessages: chatProvider.hasMoreMessages,
      isLoadingMoreMessages: chatProvider.isLoadingMoreMessages,
      isLoadingInitial: (chatProvider.isLoading || chatProvider.isLoadingSessions)
        && !chatProvider.isClearing,
      app: nil,
      onLoadMore: { await chatProvider.loadMoreMessages() },
      onRate: { messageId, rating in
        Task { await chatProvider.rateMessage(messageId, rating: rating) }
      },
      localSendToken: chatProvider.localSendToken,
      onCancelTurn: { [weak chatProvider] in chatProvider?.stopAgent(owner: .mainChat) },
      onOpenAgent: { agentID, completion in
        FloatingControlBarManager.shared.openAgentChatFromTimeline(agentID: agentID, completion: completion)
      },
      onOpenAgentRef: { ref, completion in
        FloatingControlBarManager.shared.openAgentChatFromTimeline(ref: ref, completion: completion)
      },
      horizontalContentPadding: 10,
      onContentHeightChange: onBodyHeightChange,
      welcomeContent: { welcome }
    )
  }

  private var welcome: some View {
    VStack(spacing: 6) {
      Text("Ask Omi anything")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
      Text("Your conversation continues in the main window")
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.5))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
  }
}
