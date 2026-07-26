import XCTest

@testable import Omi_Computer

/// `NotchPresentation.derive` is the single authority both the panel size and
/// the rendered content read, so every ordering rule belongs here.
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
}
