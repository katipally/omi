import OmiTheme
import SwiftUI

/// Read-only transcript for one subagent, shown over the main window.
///
/// Agent transcripts used to live only in the floating bar, which meant the
/// main window could link to an agent it had no way to display. The notch is a
/// voice surface with no agent list, so this is now the one place a spawned
/// agent's work can be read. Presented by `.openAgentTranscript`, which
/// `FloatingControlBarManager.openAgentChatFromTimeline` posts after hydrating
/// the pill.
struct AgentTranscriptSheet: ViewModifier {
  /// Held by id, not by reference: the pill is a class the manager can replace
  /// while the sheet is open, and the id is what survives a rehydrate.
  @State private var openPillID: UUID?
  @ObservedObject private var manager = AgentPillsManager.shared

  func body(content: Content) -> some View {
    content
      .onReceive(NotificationCenter.default.publisher(for: .openAgentTranscript)) { note in
        guard let id = note.object as? UUID else { return }
        openPillID = id
        // Expiration skips the pill being read, so it can't vanish mid-scroll.
        FloatingControlBarManager.shared.activeAgentChatPillID = id
      }
      .onReceive(NotificationCenter.default.publisher(for: .closeAgentTranscript)) { _ in
        close()
      }
      .sheet(isPresented: Binding(get: { openPillID != nil }, set: { if !$0 { close() } })) {
        if let id = openPillID, let pill = manager.pills.first(where: { $0.id == id }) {
          AgentTranscriptView(pill: pill, onClose: close)
        }
      }
  }

  private func close() {
    openPillID = nil
    FloatingControlBarManager.shared.activeAgentChatPillID = nil
  }
}

extension View {
  /// Lets this surface present a subagent transcript. Attach once per window.
  func agentTranscriptSheet() -> some View { modifier(AgentTranscriptSheet()) }
}

private struct AgentTranscriptView: View {
  @ObservedObject var pill: AgentPill
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(OmiColors.border.opacity(0.28))
      ChatMessagesView(
        messages: pill.conversationMessages,
        isSending: pill.status == .running,
        hasMoreMessages: false,
        isLoadingMoreMessages: false,
        isLoadingInitial: false,
        app: nil,
        onLoadMore: {},
        onRate: { _, _ in },
        welcomeContent: {
          Text(pill.latestActivity.isEmpty ? "Waiting for the agent to report back…" : pill.latestActivity)
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(OmiSpacing.xxl)
        }
      )
    }
    .frame(width: 720, height: 560)
    .background(OmiColors.backgroundSecondary)
  }

  private var header: some View {
    HStack(spacing: OmiSpacing.sm) {
      Circle()
        .fill(AgentStatusGroup(status: pill.status).color)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 1) {
        Text(pill.title)
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
          .lineLimit(1)
        if !pill.latestActivity.isEmpty {
          Text(pill.latestActivity)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: OmiSpacing.md)
      if pill.status == .running {
        OmiIconButton(systemName: "stop.fill", help: "Stop this agent") {
          AgentPillsManager.shared.stop(pillID: pill.id)
        }
      }
      OmiIconButton(systemName: "xmark", help: "Close", action: onClose)
    }
    .padding(.horizontal, OmiSpacing.xl)
    .padding(.vertical, OmiSpacing.md)
  }
}
