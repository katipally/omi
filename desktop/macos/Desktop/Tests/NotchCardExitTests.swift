import XCTest

@testable import Omi_Computer

/// The exit rule for notch cards.
///
/// A card that times out always goes away on its own. A card that does not has
/// to give the user a control that ends it and decides nothing — otherwise the
/// only ways off the screen are the decisions the card is asking for, and
/// "not now" is not one of them. The receipt card shipped with exactly that
/// hole: Review navigated away and Undo destroyed the task Omi had just saved.
final class NotchCardExitTests: XCTestCase {
  private func card(_ assistantId: String) -> FloatingBarNotification {
    FloatingBarNotification(
      ownerID: "owner",
      title: "✓ Saved to Tasks — pay the rent",
      message: "",
      assistantId: assistantId
    )
  }

  /// Enumerated from the list the dismissal policy itself reads, so a sixth
  /// variant is covered the day it is added rather than the day someone
  /// remembers this file exists.
  func testEveryCardThatNeverTimesOutOffersANeutralExit() {
    XCTAssertFalse(
      FloatingBarNotification.persistentAssistantIds.isEmpty,
      "an empty list would make this whole test vacuous"
    )

    for assistantId in FloatingBarNotification.persistentAssistantIds {
      XCTAssertFalse(
        card(assistantId).autoDismisses,
        "\(assistantId) is listed as persistent but still times out"
      )
      XCTAssertTrue(
        FloatingBarNotification.hasNeutralDismiss(assistantId: assistantId),
        "\(assistantId) stays until the user decides something, with no way to just say no"
      )
    }
  }

  /// The exits on these cards are written controls, so the copy is part of the
  /// contract: an empty label is a control the pointer can find and the eye
  /// cannot.
  func testEveryPersistentCardsExitIsLabelled() {
    for assistantId in FloatingBarNotification.persistentAssistantIds {
      let label = FloatingBarNotification.neutralDismissLabel(assistantId: assistantId)
      XCTAssertNotNil(label, "\(assistantId) has no exit copy to render")
      XCTAssertFalse(label?.isEmpty ?? true, "\(assistantId) renders a blank exit")
    }
  }

  /// The proactive card is the one variant whose exit is a glyph rather than a
  /// word, and the one that goes away by itself anyway.
  func testTheProactiveCardTimesOutAndKeepsItsGlyphExit() {
    for assistantId in ["task", "proactive_assistant"] {
      XCTAssertTrue(card(assistantId).autoDismisses)
      XCTAssertNil(FloatingBarNotification.neutralDismissLabel(assistantId: assistantId))
      XCTAssertTrue(FloatingBarNotification.hasNeutralDismiss(assistantId: assistantId))
    }
  }
}
