import OmiTheme
import SwiftUI

/// Everything the notch shows below the closed chrome that isn't a voice turn.
///
/// Five variants, all keyed off `assistantId`, so there is exactly one place
/// that decides what a notification looks like:
///
/// | assistantId      | card            | actions          | dismissal |
/// |------------------|-----------------|------------------|-----------|
/// | (anything else)  | bell            | tap to open      | auto, 6s  |
/// | `task`           | bell            | Execute, X       | auto, 6s  |
/// | `reach_error`    | warning         | Retry / Skip     | on action |
/// | `notch_receipt`  | saved-to-tasks  | Review / Undo    | on action |
/// | `notch_end`      | follow-ups      | Review / Later   | on action |
struct NotchNotificationCard: View {
  let notification: FloatingBarNotification

  var body: some View {
    switch notification.assistantId {
    case "reach_error": reachErrorCard
    case NotchMoment.receiptAssistantId: receiptCard
    case NotchMoment.endAssistantId: endOfConversationCard
    default: notificationCard
    }
  }

  private var isTask: Bool { notification.assistantId == "task" }

  // MARK: - Standard proactive notification

  private var notificationCard: some View {
    Button {
      FloatingControlBarManager.shared.openNotificationAsChat(notification)
    } label: {
      HStack(alignment: .top, spacing: OmiSpacing.sm) {
        ZStack {
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .fill(Color.white.opacity(0.08))
            .frame(width: 34, height: 34)

          Image(systemName: "bell.badge.fill")
            .scaledFont(size: 14, weight: .semibold)
            .foregroundColor(.white)
        }

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(notification.title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(.white)
            .lineLimit(1)

          Text(notification.message)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(.white.opacity(0.72))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        // Reserve space so text never runs under the overlaid action buttons.
        Color.clear
          .frame(width: isTask ? 90 : 36, height: 18)
      }
      .padding(OmiSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      HStack(spacing: OmiSpacing.xs) {
        if isTask { executeButton }
        Button {
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Image(systemName: "xmark")
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundColor(.white.opacity(0.62))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
      }
      .padding(OmiSpacing.md)
    }
  }

  /// Only meaningful for actionable (task) notifications: hands the task to an
  /// agent instead of opening it as a chat.
  private var executeButton: some View {
    Button {
      let model =
        ShortcutSettings.shared.selectedModel.isEmpty
        ? ModelQoS.Claude.defaultSelection
        : ShortcutSettings.shared.selectedModel
      let query = ProactiveTaskExecute.buildQuery(
        title: notification.title,
        message: notification.message
      )
      _ = AgentPillsManager.shared.spawn(
        query: query,
        model: model,
        originSurface: .floatingBar,
        systemPromptSuffix: ProactiveTaskExecute.systemPromptSuffix
      )
      FloatingControlBarManager.shared.dismissCurrentNotification()
    } label: {
      HStack(spacing: OmiSpacing.xxs) {
        Image(systemName: "sparkles")
          .scaledFont(size: 9, weight: .bold)
        Text("Execute")
          .scaledFont(size: OmiType.micro, weight: .semibold)
      }
      .foregroundColor(.white)
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.xxs)
      .background(Color.white.opacity(0.18))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .help("Spawn an agent to handle this")
  }

  // MARK: - Reach error

  /// Hard reach failure (retries exhausted). Persists until the user picks
  /// Retry (re-runs the query, restarting backoff) or Skip (back to idle).
  private var reachErrorCard: some View {
    HStack(alignment: .center, spacing: OmiSpacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .scaledFont(size: 14, weight: .semibold)
        .foregroundColor(.white.opacity(0.9))

      VStack(alignment: .leading, spacing: 1) {
        Text(notification.title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(.white)
          .lineLimit(1)
        if !notification.message.isEmpty {
          Text(notification.message)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
        }
      }

      Spacer(minLength: OmiSpacing.sm)

      Button {
        FloatingControlBarManager.shared.retryReachError()
      } label: {
        Text("Retry")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(.white)
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.xxs)
          .background(Color.white.opacity(0.18))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      Button {
        FloatingControlBarManager.shared.dismissReachError()
      } label: {
        Text("Skip")
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(.white.opacity(0.6))
          .padding(.horizontal, OmiSpacing.xs)
          .padding(.vertical, OmiSpacing.xxs)
      }
      .buttonStyle(.plain)
    }
    .padding(OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Task receipt

  /// Durable receipt — "Saved to Tasks — <task>" with Review and Undo, posted
  /// only after Omi can read the task back through the canonical action-items
  /// path. Monochrome; the save already happened, so this is a report, not an
  /// alert.
  private var receiptCard: some View {
    HStack(spacing: OmiSpacing.sm) {
      Text(notification.title)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(.white)
        .lineLimit(1)
      Spacer(minLength: OmiSpacing.sm)
      Button {
        NotchMomentsCoordinator.shared.reviewLastReceipt()
        FloatingControlBarManager.shared.dismissCurrentNotification()
      } label: {
        Text("Review")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(.white)
          .underline()
      }
      .buttonStyle(.plain)
      Button {
        NotchMomentsCoordinator.shared.undoLastReceipt()
        FloatingControlBarManager.shared.dismissCurrentNotification()
      } label: {
        Text("Undo")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(.white.opacity(0.55))
          .underline()
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - End of conversation

  /// A conversation just ended and left follow-ups behind. The one card that
  /// leads with a filled button, because acting on it is the point.
  private var endOfConversationCard: some View {
    VStack(alignment: .leading, spacing: 2) {
      if !notification.message.isEmpty {
        Text(notification.message)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(.white.opacity(0.55))
          .lineLimit(1)
      }
      Text(notification.title)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(.white)
        .lineLimit(1)
      HStack(spacing: OmiSpacing.xs) {
        Button {
          NotchMomentsCoordinator.shared.reviewFollowUps()
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Text("Review")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(.black)
            .padding(.horizontal, OmiSpacing.sm)
            .padding(.vertical, OmiSpacing.xxs)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: OmiChrome.badgeRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        Button {
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Text("Later")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
      }
      .padding(.top, OmiSpacing.xxs)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
