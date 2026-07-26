import OmiTheme
import SwiftUI

/// Everything the notch shows below the closed chrome that isn't a voice turn.
///
/// Five variants, all keyed off `assistantId`, so there is exactly one place
/// that decides what a notification looks like:
///
/// | assistantId      | card            | actions                  | dismissal |
/// |------------------|-----------------|--------------------------|-----------|
/// | (anything else)  | bell            | tap to open              | auto, 6s  |
/// | `task`           | bell            | Execute, X               | auto, 6s  |
/// | `reach_error`    | warning         | Retry / Skip             | on action |
/// | `notch_receipt`  | saved-to-tasks  | Review / Undo / Dismiss  | on action |
/// | `notch_end`      | follow-ups      | Review / Later           | on action |
///
/// Every variant lays out its actions as a row in the flow. The card reports its
/// intrinsic height to the panel, so a variant that overlaid its buttons would
/// be measuring a box the buttons are not inside — and any copy long enough to
/// reach them would run underneath.
///
/// The right-hand control of every card that does not time out is the neutral
/// exit: it ends the card and takes no action at all. Its label comes from
/// `FloatingBarNotification.neutralDismissLabel`, so the rule that a persistent
/// card must have one is answered about the control the user can actually see.
struct NotchNotificationCard: View {
  let notification: FloatingBarNotification

  @Environment(\.sbTheme) private var sb
  @State private var isHovering = false

  var body: some View {
    switch notification.assistantId {
    case "reach_error": reachErrorCard
    case NotchMoment.receiptAssistantId: receiptCard
    case NotchMoment.endAssistantId: endOfConversationCard
    default: notificationCard
    }
  }

  private var isTask: Bool { notification.assistantId == "task" }

  /// The copy on this variant's neutral exit, or nil where the exit is the
  /// dismiss glyph. Read straight from the shared rule rather than written into
  /// each variant, so deleting the rule deletes the control with it.
  private var neutralExitLabel: String? {
    FloatingBarNotification.neutralDismissLabel(assistantId: notification.assistantId)
  }

  /// The full notification, untruncated, for assistive technology.
  private var spokenSummary: String {
    notification.message.isEmpty
      ? notification.title
      : "\(notification.title). \(notification.message)"
  }

  // MARK: - Ink
  //
  // Three registers for the whole card. The variants used to reach for their own
  // white opacities and rendered the same supporting caption at five different
  // greys; naming them here is what keeps the five reading as one surface.

  /// Titles and anything the eye should land on first.
  private var titleInk: Color { sb.pillInkSolid }
  /// Supporting copy: messages, eyebrows, secondary captions.
  private var bodyInk: Color { sb.pillInk(.w7) }
  /// Deliberately recessive controls — the "not now" half of a pair.
  private var mutedInk: Color { sb.pillInk(.w45) }

  // MARK: - Standard proactive notification

  /// Tapping the copy opens the notification as a chat; the actions sit beside
  /// it as siblings, so the text lane ends exactly where they begin.
  private var notificationCard: some View {
    HStack(alignment: .top, spacing: OmiSpacing.sm) {
      Button {
        FloatingControlBarManager.shared.openNotificationAsChat(notification)
      } label: {
        HStack(alignment: .top, spacing: OmiSpacing.sm) {
          bellIcon
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text(notification.title)
              .scaledFont(size: OmiType.body, weight: .semibold)
              .foregroundColor(titleInk)
              .lineLimit(titleLineLimit)
              .truncationMode(.tail)
              .fixedSize(horizontal: false, vertical: true)

            if !notification.message.isEmpty {
              Text(notification.message)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(bodyInk)
                .lineLimit(messageLineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .multilineTextAlignment(.leading)
          // The copy owns every point the actions don't, so the text lane is a
          // consequence of the layout instead of a number that has to be kept
          // in step with whatever the buttons happen to measure.
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // Spelled out rather than combined from the children: the copy is
      // truncated on screen, and VoiceOver should read the notification, not
      // whatever fitted in the lane.
      .accessibilityLabel(spokenSummary)
      .accessibilityHint("Opens this notification as a chat")

      // The actions share the icon well's band and center inside it, so the row
      // reads level against the bell however many lines the copy wraps to —
      // top-aligning the raw controls would hang them a few points high.
      HStack(spacing: OmiSpacing.xs) {
        if isTask { executeButton }
        dismissButton
      }
      .frame(height: iconWell)
    }
    .padding(OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
        .fill(sb.pillInk(.w04))
        .opacity(isHovering ? 1 : 0)
    }
    .onHover { isHovering = $0 }
    .omiAnimation(SBMotion.standard, value: isHovering)
  }

  private var bellIcon: some View {
    ZStack {
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
        .fill(sb.pillInk(.w08))
        .frame(width: iconWell, height: iconWell)

      Image(systemName: "bell.badge.fill")
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(titleInk)
    }
  }

  private var dismissButton: some View {
    Button {
      FloatingControlBarManager.shared.dismissCurrentNotification()
    } label: {
      Image(systemName: "xmark")
        .scaledFont(size: OmiType.micro, weight: .bold)
        .foregroundColor(bodyInk)
        // The drawn well and the hit area are separate frames on purpose: the
        // well is sized to read correctly beside the bell, and the area around
        // it is sized to clear the pointer-target minimum.
        .frame(width: 22, height: 22)
        .background(sb.pillInk(.w08), in: Circle())
        .frame(width: 30, height: iconWell)
        .contentShape(Rectangle())
    }
    .buttonStyle(NotchCardControlStyle())
    .accessibilityLabel("Dismiss")
    .help("Dismiss this notification")
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
          .scaledFont(size: OmiType.micro, weight: .bold)
        Text("Execute")
          .scaledFont(size: OmiType.micro, weight: .semibold)
      }
      .foregroundColor(titleInk)
      .padding(.horizontal, OmiSpacing.sm)
      .frame(height: controlHeight)
      .background(sb.pillInk(.w18), in: Capsule())
      .frame(height: iconWell)
      .contentShape(Rectangle())
    }
    .buttonStyle(NotchCardControlStyle())
    .accessibilityLabel("Execute this task")
    .help("Spawn an agent to handle this")
  }

  // MARK: - Reach error

  /// Hard reach failure (retries exhausted). Persists until the user picks
  /// Retry (re-runs the query, restarting backoff) or Skip (back to idle).
  private var reachErrorCard: some View {
    HStack(alignment: .top, spacing: OmiSpacing.sm) {
      // Baseline-aligned, not top-aligned: the warning glyph belongs on the
      // title's first line, and a top alignment hangs it a few points high the
      // moment the message underneath wraps.
      HStack(alignment: .firstTextBaseline, spacing: OmiSpacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(titleInk)

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(notification.title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(titleInk)
            .lineLimit(titleLineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
          if !notification.message.isEmpty {
            Text(notification.message)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(bodyInk)
              .lineLimit(messageLineLimit)
              .truncationMode(.tail)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: OmiSpacing.xs) {
        Button {
          FloatingControlBarManager.shared.retryReachError()
        } label: {
          filledLabel("Retry")
        }
        .buttonStyle(NotchCardControlStyle())
        .help("Run the request again")

        if let exit = neutralExitLabel {
          Button {
            // Not the plain dismissal: giving up on the request is what
            // releases the retry closure the card was holding.
            FloatingControlBarManager.shared.dismissReachError()
          } label: {
            quietLabel(exit)
          }
          .buttonStyle(NotchCardControlStyle())
          .help("Give up on this request")
        }
      }
    }
    .padding(OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Task receipt

  /// Durable receipt — "Saved to Tasks — <task>", posted only after Omi can read
  /// the task back through the canonical action-items path. Monochrome; the save
  /// already happened, so this is a report, not an alert — which is exactly why
  /// its third control has to exist. Review navigates away and Undo destroys the
  /// task; "seen it" was left with nothing to press.
  private var receiptCard: some View {
    HStack(alignment: .center, spacing: OmiSpacing.sm) {
      Text(notification.title)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(titleInk)
        .lineLimit(titleLineLimit)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: OmiSpacing.xs) {
        Button {
          NotchMomentsCoordinator.shared.reviewLastReceipt()
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          linkLabel("Review", ink: titleInk)
        }
        .buttonStyle(NotchCardControlStyle())
        .help("Open the saved task")

        Button {
          NotchMomentsCoordinator.shared.undoLastReceipt()
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          linkLabel("Undo", ink: mutedInk)
        }
        .buttonStyle(NotchCardControlStyle())
        .help("Remove the task that was just saved")

        if let exit = neutralExitLabel {
          Button {
            FloatingControlBarManager.shared.dismissCurrentNotification()
          } label: {
            linkLabel(exit, ink: mutedInk)
          }
          .buttonStyle(NotchCardControlStyle())
          .help("Keep the task and put the receipt away")
        }
      }
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - End of conversation

  /// A conversation just ended and left follow-ups behind. The one card that
  /// leads with a filled button, because acting on it is the point.
  private var endOfConversationCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      if !notification.message.isEmpty {
        Text(notification.message)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(mutedInk)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Text(notification.title)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(titleInk)
        .lineLimit(titleLineLimit)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)

      HStack(spacing: OmiSpacing.xs) {
        Button {
          NotchMomentsCoordinator.shared.reviewFollowUps()
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Text("Review")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(sb.pillInkInverted)
            .padding(.horizontal, OmiSpacing.sm)
            .frame(height: controlHeight)
            .background(
              sb.pillInkSolid,
              in: RoundedRectangle(cornerRadius: OmiChrome.badgeRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchCardControlStyle())
        .help("Open the follow-ups this conversation left behind")

        if let exit = neutralExitLabel {
          Button {
            FloatingControlBarManager.shared.dismissCurrentNotification()
          } label: {
            quietLabel(exit)
          }
          .buttonStyle(NotchCardControlStyle())
          .help("Dismiss without opening the follow-ups")
        }
      }
      .padding(.top, OmiSpacing.xxs)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
  }

  // MARK: - Shared labels

  /// Caps that keep a runaway string from turning the notch into a panel. The
  /// card's height is measured, so without them there is nothing to stop it —
  /// and the copy truncates rather than clipping, so the last line always ends
  /// in a readable ellipsis.
  private var titleLineLimit: Int { 2 }
  private var messageLineLimit: Int { 4 }

  /// The proactive card's leading icon well. Its action row shares the band.
  private var iconWell: CGFloat { 34 }
  /// One height for every control on a card, so a filled pill, a plain label and
  /// an underlined link sit on the same line whichever variant is showing.
  private var controlHeight: CGFloat { 24 }

  private func filledLabel(_ text: String) -> some View {
    Text(text)
      .scaledFont(size: OmiType.caption, weight: .semibold)
      .foregroundColor(titleInk)
      .padding(.horizontal, OmiSpacing.sm)
      .frame(height: controlHeight)
      .background(sb.pillInk(.w18), in: Capsule())
      .contentShape(Capsule())
  }

  private func quietLabel(_ text: String) -> some View {
    Text(text)
      .scaledFont(size: OmiType.caption, weight: .semibold)
      .foregroundColor(mutedInk)
      .padding(.horizontal, OmiSpacing.sm)
      .frame(height: controlHeight)
      .contentShape(Rectangle())
  }

  private func linkLabel(_ text: String, ink: Color) -> some View {
    Text(text)
      .scaledFont(size: OmiType.caption)
      .foregroundColor(ink)
      .underline()
      .padding(.horizontal, OmiSpacing.xs)
      .frame(height: controlHeight)
      .contentShape(Rectangle())
  }
}

// MARK: - Control feedback

/// Hover, press and disabled feedback for every control on a notch card.
///
/// Deliberately not `OmiButtonStyle`: that primitive owns its own fill, padding
/// and main-window sizing, while these controls are 24pt tall on black glass and
/// each carries its own shape. What has to be shared here is the *response* to
/// the pointer, so the response is all this style owns.
private struct NotchCardControlStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Feedback(configuration: configuration)
  }

  private struct Feedback: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
      configuration.label
        .opacity(opacity)
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .onHover { isHovering = $0 }
        .omiAnimation(SBMotion.toggle, value: isHovering)
        .omiAnimation(SBMotion.toggle, value: configuration.isPressed)
    }

    /// Resting slightly under full strength so hover has somewhere to go. On
    /// black glass an opacity lift reads more cleanly than a second fill, which
    /// would compete with the shapes the labels already carry.
    private var opacity: Double {
      guard isEnabled else { return 0.35 }
      if configuration.isPressed { return 0.55 }
      return isHovering ? 1 : 0.88
    }
  }
}
