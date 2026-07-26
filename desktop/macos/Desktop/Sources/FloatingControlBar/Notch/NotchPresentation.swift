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
}
