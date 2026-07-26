import XCTest

@testable import Omi_Computer

/// `NotchPresentation` is the single authority the panel size, the rendered
/// content and the outside-click policy all read, so every ordering rule
/// belongs here.
final class NotchPresentationTests: XCTestCase {
  private func derive(
    listening: Bool = false,
    thinking: Bool = false,
    responding: Bool = false,
    hint: String = "",
    notification: UUID? = nil,
    isVoiceDisplay: Bool = true
  ) -> NotchPresentation {
    NotchPresentation.derive(
      isListening: listening,
      isThinking: thinking,
      isResponding: responding,
      hintText: hint,
      notificationID: notification,
      isVoiceDisplay: isVoiceDisplay
    )
  }

  func testLadderOrdering() {
    XCTAssertEqual(derive(), .idle)
    XCTAssertEqual(derive(listening: true, thinking: true, responding: true), .listening)
    // The reducer reports thinking and responding together while it waits; the
    // compact pill has to hold until the reply actually starts arriving.
    XCTAssertEqual(derive(thinking: true, responding: true), .thinking)
    XCTAssertEqual(derive(responding: true, hint: "Hold longer to record"), .responding)
    XCTAssertEqual(derive(hint: "Microphone unavailable"), .hint("Microphone unavailable"))
  }

  func testNotificationOnlySurfacesOnceTheVoiceTurnIsDone() {
    let id = UUID()
    XCTAssertEqual(derive(responding: true, notification: id), .responding)
    XCTAssertEqual(derive(notification: id), .notification(id))
  }

  // MARK: - One turn, one display

  func testVoiceSurfacesAreSuppressedOffTheTurnsDisplay() {
    XCTAssertEqual(derive(listening: true, isVoiceDisplay: false), .idle)
    XCTAssertEqual(derive(thinking: true, isVoiceDisplay: false), .idle)
    XCTAssertEqual(derive(responding: true, isVoiceDisplay: false), .idle)
    XCTAssertEqual(derive(hint: "Microphone unavailable", isVoiceDisplay: false), .idle)
  }

  func testNotificationsStillReachEveryDisplay() {
    let id = UUID()
    XCTAssertEqual(derive(notification: id, isVoiceDisplay: false), .notification(id))
    // A turn running elsewhere must not hide a notification on this display.
    XCTAssertEqual(
      derive(listening: true, notification: id, isVoiceDisplay: false), .notification(id))
  }

  // MARK: - Layer predicates

  func testVoiceTurnPredicateCoversExactlyTheTravellingMarkStates() {
    XCTAssertTrue(NotchPresentation.listening.isVoiceTurn)
    XCTAssertTrue(NotchPresentation.thinking.isVoiceTurn)
    XCTAssertTrue(NotchPresentation.responding.isVoiceTurn)
    XCTAssertFalse(NotchPresentation.idle.isVoiceTurn)
    XCTAssertFalse(NotchPresentation.hint("x").isVoiceTurn)
    XCTAssertFalse(NotchPresentation.notification(UUID()).isVoiceTurn)
  }

  func testExpandedSurfaceIsTheShadowRuleNotTheVoiceRule() {
    // Thinking is the compact pill between the two grown states, and a
    // notification is a panel that never involves the voice turn — the two
    // predicates deliberately disagree on both.
    XCTAssertFalse(NotchPresentation.thinking.isExpandedSurface)
    XCTAssertTrue(NotchPresentation.notification(UUID()).isExpandedSurface)
  }

  // MARK: - The linger overlay

  private func resolve(
    listening: Bool = false,
    thinking: Bool = false,
    responding: Bool = false,
    hint: String = "",
    notification: UUID? = nil,
    isVoiceDisplay: Bool = true,
    lingering: Bool = false
  ) -> NotchPresentation {
    NotchPresentation.resolve(
      isListening: listening,
      isThinking: thinking,
      isResponding: responding,
      hintText: hint,
      notificationID: notification,
      isVoiceDisplay: isVoiceDisplay,
      isLingeringReply: lingering
    )
  }

  /// The whole ladder in one place: the view that renders a panel and the
  /// manager that decides what a click off it means both read this, so the
  /// linger overlay has to live here rather than in either caller.
  func testAFinishedReplyHoldsThePanelInsteadOfCollapsing() {
    XCTAssertEqual(resolve(lingering: true), .responding)
    // A card that arrived while the reply was still being read waits its turn.
    XCTAssertEqual(resolve(notification: UUID(), lingering: true), .responding)
  }

  func testALingeringReplyNeverOutranksTheNextTurnOrAnError() {
    XCTAssertEqual(resolve(listening: true, lingering: true), .listening)
    XCTAssertEqual(resolve(thinking: true, lingering: true), .thinking)
    XCTAssertEqual(
      resolve(hint: "Microphone unavailable", lingering: true), .hint("Microphone unavailable"))
  }

  func testALingeringReplyStaysOnItsOwnDisplay() {
    let id = UUID()
    XCTAssertEqual(resolve(isVoiceDisplay: false, lingering: true), .idle)
    XCTAssertEqual(
      resolve(notification: id, isVoiceDisplay: false, lingering: true), .notification(id))
  }

  func testResolveAgreesWithDeriveWhenNothingLingers() {
    let id = UUID()
    XCTAssertEqual(resolve(), derive())
    XCTAssertEqual(resolve(listening: true), derive(listening: true))
    XCTAssertEqual(resolve(notification: id), derive(notification: id))
  }

  // MARK: - What a click off the notch means

  /// Killing a hold, the wait, or a reply that is still arriving because the
  /// pointer landed somewhere else is worse than any amount of clutter.
  func testALiveVoiceTurnSurvivesAClickElsewhere() {
    for presentation in [NotchPresentation.listening, .thinking, .responding] {
      XCTAssertEqual(
        presentation.outsideClickOutcome(isVoiceTurnActive: true), .ignored,
        "\(presentation) was dismissed mid-turn"
      )
    }
  }

  /// The same presentation covers the reply as it streams and the reply once it
  /// has finished, so the turn's own liveness is the whole difference.
  func testAFinishedReplyIsWhatAClickElsewherePutsAway() {
    XCTAssertEqual(
      NotchPresentation.responding.outsideClickOutcome(isVoiceTurnActive: false),
      .lingeringReply
    )
  }

  /// Every card answers the same way. The presentation carries the card's id and
  /// not its variant, which is what makes it impossible for one kind of card —
  /// the reach error, with its Retry — to take a different action here.
  func testEveryCardIsPutAwayAndNothingElseHappens() {
    for turnActive in [true, false] {
      for id in [UUID(), UUID()] {
        XCTAssertEqual(
          NotchPresentation.notification(id).outsideClickOutcome(isVoiceTurnActive: turnActive),
          .notification
        )
      }
    }
  }

  func testASurfaceWithNothingToPutAwayIsLeftAlone() {
    XCTAssertEqual(NotchPresentation.idle.outsideClickOutcome(isVoiceTurnActive: false), .ignored)
    XCTAssertEqual(
      NotchPresentation.hint("Hold longer to record").outsideClickOutcome(isVoiceTurnActive: false),
      .ignored
    )
  }
}
