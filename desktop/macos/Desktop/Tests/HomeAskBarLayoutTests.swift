import XCTest

@testable import Omi_Computer

/// The ask bar's trailing slot swaps between four different views. The pill is a
/// bottom-aligned row, so any one of them being taller than the others resizes
/// the whole bar as the user focuses the field or starts a send.
///
/// The equal-height property itself is enforced by construction rather than by a
/// test: `actionButton` applies one `.frame(height:)` outside the switch, so no
/// arm can set its own. What is worth testing is the rule that decides which arm
/// shows, because that is real branching logic.
final class HomeAskBarLayoutTests: XCTestCase {
  func testActionModePrecedence() {
    // A send in flight outranks everything: the user needs Stop reachable even
    // with a draft still in the field and focus still held.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: true, canSend: true, isFocused: true),
      .stop
    )
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: true, canSend: false, isFocused: false),
      .stop
    )

    // Text present, nothing in flight: send, focused or not.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: true, isFocused: true),
      .send
    )
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: true, isFocused: false),
      .send
    )

    // Focused and empty: the slot is deliberately empty. Connect would be a
    // second affordance competing with the field the user just clicked into.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: false, isFocused: true),
      .none
    )

    // At rest: Connect is the resting affordance.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: false, isFocused: false),
      .connect
    )
  }

  func testTheAccessorySlotReservesRoomForTheWidestControl() {
    // The original defect was a 34pt capsule beside a 30pt circle: the bar was
    // 48pt with Connect showing and 44pt without, so clicking into the field
    // moved it. One height for the slot is what removes the difference, and the
    // measured-width path has to reserve at least that much chrome.
    XCTAssertGreaterThan(HomeAskBarMetrics.accessoryHeight, 0)
    XCTAssertGreaterThan(
      HomeAskBarMetrics.accessoryReserve,
      HomeAskBarMetrics.accessoryHeight,
      "the reserve covers the widest accessory plus its trailing inset"
    )
  }
}
