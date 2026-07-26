import Foundation

/// The single, authoritative description of what the notch is showing right
/// now. Both the panel size (`NotchViewModel.size(for:)`) and the rendered
/// content (`NotchView.bodyContent`) derive from this one value, so they can
/// never disagree.
///
/// The notch is a voice surface: it has no panel to open and no tabs. Every
/// case here is something a voice turn, an error, or a proactive notification
/// puts on screen; text input lives in the main app.
enum NotchPresentation: Equatable {
  case listening
  case thinking
  case responding
  case hint(String)
  case notification(UUID)
  case idle

  /// Whether the black body should cast its expanded shadow. The two grown
  /// voice states plus the notification card read as a panel that came out of
  /// the camera housing; thinking is the compact pill between them.
  var isExpandedSurface: Bool {
    switch self {
    case .listening, .responding, .notification: return true
    case .thinking, .hint, .idle: return false
    }
  }

  /// Whether a voice turn is on screen. The Omi mark leaves its chrome lobe and
  /// travels to the centered orb slot for exactly these, so it is the same mark
  /// that becomes the waveform rather than one fading out as another fades in.
  var isVoiceTurn: Bool {
    switch self {
    case .listening, .thinking, .responding: return true
    case .hint, .notification, .idle: return false
    }
  }

  /// The priority ladder: the voice turn runs listening -> thinking ->
  /// responding, then passive surfaces. Pure, so the ordering is unit-testable.
  ///
  /// Three things here are load-bearing:
  /// - Thinking beats responding, because the reducer reports both while it is
  ///   waiting for the answer; the compact pill should hold until the reply
  ///   actually starts arriving.
  /// - `isListening` must be the reducer's raw listening phase
  ///   (`FloatingControlBarState.isListeningPhase`), NOT `isVoiceListening`,
  ///   which folds the hint in. Pass the folded one and every actionable PTT
  ///   error ("Microphone unavailable", "Hold longer to record") outranks its
  ///   own hint and renders as a shimmering "Listening...".
  /// - A voice turn belongs to one display: the one the pointer was on when it
  ///   started. Every other panel passes `isVoiceDisplay: false` and skips the
  ///   four voice rungs, so a hold lights up one screen instead of all of them.
  ///   Notifications are not voice and reach every display.
  static func derive(
    isListening: Bool,
    isThinking: Bool,
    isResponding: Bool,
    hintText: String,
    notificationID: UUID?,
    isVoiceDisplay: Bool = true
  ) -> NotchPresentation {
    if isVoiceDisplay {
      if isListening { return .listening }
      if isThinking { return .thinking }
      if isResponding { return .responding }
      if !hintText.isEmpty { return .hint(hintText) }
    }
    if let notificationID { return .notification(notificationID) }
    return .idle
  }

  /// `derive` plus the linger overlay: a finished reply still on screen holds
  /// the panel in `.responding` rather than letting it fall through to idle or
  /// to a card queued behind it. This is the whole ladder, so the view that
  /// renders a panel and the manager that decides what a click off it means are
  /// reading one answer rather than two that can drift apart.
  static func resolve(
    isListening: Bool,
    isThinking: Bool,
    isResponding: Bool,
    hintText: String,
    notificationID: UUID?,
    isVoiceDisplay: Bool,
    isLingeringReply: Bool
  ) -> NotchPresentation {
    let base = derive(
      isListening: isListening,
      isThinking: isThinking,
      isResponding: isResponding,
      hintText: hintText,
      notificationID: notificationID,
      isVoiceDisplay: isVoiceDisplay
    )
    guard isLingeringReply, isVoiceDisplay else { return base }
    switch base {
    case .idle, .notification: return .responding
    default: return base
    }
  }

  /// What a click somewhere off the notch does to what is currently on screen.
  ///
  /// A live voice turn is never dismissible: killing a hold, the wait, or a
  /// reply that is still arriving because the pointer landed somewhere else is
  /// worse than any amount of clutter. What a click can put away is a surface
  /// that is only waiting to be read — a finished reply lingering, or a card.
  ///
  /// `isVoiceTurnActive` is the whole difference between the two `.responding`
  /// cases: the same presentation covers the reply as it streams and the reply
  /// once it has finished.
  func outsideClickOutcome(isVoiceTurnActive: Bool) -> NotchOutsideClickOutcome {
    switch self {
    case .listening, .thinking: return .ignored
    case .responding: return isVoiceTurnActive ? .ignored : .lingeringReply
    case .notification: return .notification
    case .hint, .idle: return .ignored
    }
  }
}

/// The outcome of a click off the notch. Deliberately not a Bool: every case
/// that can be dismissed is dismissed differently, and keeping the choice in one
/// value is what stops the policy from being half in a predicate and half in the
/// caller's switch.
enum NotchOutsideClickOutcome: Equatable {
  /// Nothing on this panel answers to an outside click.
  case ignored
  /// A finished reply that is only waiting to be read.
  case lingeringReply
  /// A notification card. Dismissed and NOTHING else: nothing retried, undone,
  /// or deleted, whatever the card's own buttons offer. A card queued behind it
  /// takes its place, exactly as it would if the card had timed out.
  case notification
}
