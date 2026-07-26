import XCTest

@testable import Omi_Computer

/// Three defects shared one cause: the transcript's geometry was derived from
/// something that moves. The scroll view was capped to the readable column, so
/// the macOS overlay scroller floated inside the shell instead of riding its
/// edge. The fade was a fraction of the panel, so it re-scaled every time the
/// composer grew a line. And the send re-anchor fired inside the insert spring,
/// so a row was snapped into place while it was still arriving.
///
/// Two of those are now structural — the cap lives on the column and the mask
/// lives inside `ChatMessagesView` — and are not restated here as source
/// scrapes. The timing rule is real branching arithmetic and is.
final class HomeTranscriptLayoutTests: XCTestCase {

  func testTheSendSettleWaitsOutTheInsertSpring() {
    // `.spring(response: 0.38)` is not finished at 0.38 — response is the
    // period, not the settle. A re-anchor scheduled inside that window assigns
    // an offset the spring is still integrating toward, which is the snap.
    XCTAssertGreaterThan(ChatSendMotion.settleDelay, 0.38)
    // But not so late that a tall row stays half-off-screen while the user
    // waits for it.
    XCTAssertLessThan(ChatSendMotion.settleDelay, 0.6)
  }

  func testTheRiseStartsBelowTheRestingRow() {
    // The bubble has to arrive from where the composer is, or the motion reads
    // as a fade rather than as the text leaving the field.
    XCTAssertGreaterThan(ChatSendMotion.riseDistance, 0)
    XCTAssertLessThan(ChatSendMotion.enteringScale, 1)
  }

  func testTheFollowOutlivesTheStream() {
    // The reveal is paced on its own clock, so the transcript keeps growing
    // after the last token. Ending the follow with the stream would strand that
    // tail below the fold.
    XCTAssertGreaterThan(ChatStreamScroll.settleTail, 0)
    XCTAssertGreaterThan(ChatStreamScroll.settleTail, ChatSendMotion.settleDelay)
  }

  func testTurnSpacingSeparatesTurnsMoreThanTheirParts() {
    // A flat gap makes a question and its answer look as unrelated as two
    // separate exchanges.
    XCTAssertGreaterThan(ChatTurnSpacing.betweenTurns, ChatTurnSpacing.withinTurn)
    XCTAssertEqual(ChatTurnSpacing.leadingGap(previous: nil, current: .user), 0)
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .ai, current: .user),
      ChatTurnSpacing.betweenTurns
    )
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .user, current: .ai),
      ChatTurnSpacing.withinTurn
    )
  }
}
