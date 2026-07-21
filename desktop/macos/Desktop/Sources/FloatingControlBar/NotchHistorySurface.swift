import OmiTheme
import SwiftUI

/// Browse + resume past chat sessions from inside the notch. Selecting a session
/// resumes it through the shared provider (`selectSession`) — no second store
/// (INV-CHAT-1). Voice is unaffected (push-to-talk).
struct NotchHistorySurface: View {
  @ObservedObject var state: FloatingControlBarState
  @ObservedObject var chatProvider: ChatProvider

  var body: some View {
    Group {
      if chatProvider.isLoadingSessions && chatProvider.sessions.isEmpty {
        centered { ProgressView().scaleEffect(0.7) }
      } else if let error = chatProvider.sessionsLoadError, chatProvider.sessions.isEmpty {
        centered {
          Text(error)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
      } else if chatProvider.groupedSessions.isEmpty {
        centered {
          Text("No past chats yet")
            .scaledFont(size: OmiType.body)
            .foregroundColor(.secondary)
        }
      } else {
        sessionsList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var sessionsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: OmiSpacing.sm, pinnedViews: [.sectionHeaders]) {
        ForEach(chatProvider.groupedSessions, id: \.0) { group, sessions in
          Section {
            ForEach(sessions) { session in
              sessionRow(session)
            }
          } header: {
            Text(group)
              .scaledFont(size: OmiType.micro, weight: .semibold)
              .foregroundColor(.secondary)
              .textCase(.uppercase)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, OmiSpacing.xxs)
              .background(OmiColors.backgroundPrimary.opacity(0.9))
          }
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.bottom, OmiSpacing.md)
    }
  }

  private func sessionRow(_ session: ChatSession) -> some View {
    let selected = chatProvider.currentSession?.id == session.id
    return Button {
      let target = session
      Task { @MainActor in
        await chatProvider.selectSession(target)
        state.hydrateViewport(from: chatProvider)
        state.conversationSurface = .mainResponse
        OmiMotion.withGated(.spring(response: 0.32, dampingFraction: 0.82)) {
          state.notchChatSurface = .chat
        }
      }
    } label: {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        HStack(spacing: OmiSpacing.xs) {
          if session.starred {
            Image(systemName: "star.fill")
              .scaledFont(size: OmiType.micro)
              .foregroundColor(.white.opacity(0.7))
          }
          Text(session.title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(.white)
            .lineLimit(1)
        }
        if let preview = session.preview, !preview.isEmpty {
          Text(preview)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(Color.white.opacity(selected ? 0.14 : 0.06))
      .cornerRadius(OmiChrome.elementRadius)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack { content() }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .padding(OmiSpacing.lg)
  }
}
