import XCTest

@testable import Omi_Computer

/// Three defects shared one cause: the transcript's geometry was derived from
/// something that moves. The scroll view was capped to the readable column, so
/// the macOS overlay scroller floated inside the shell instead of riding its
/// edge. The fade was a fraction of the panel, so it re-scaled every time the
/// composer grew a line. And the send re-anchor fired inside the insert spring,
/// so a row was snapped into place while it was still arriving.
final class HomeTranscriptLayoutTests: XCTestCase {

  // MARK: - Send motion

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

  // MARK: - Column width

  func testUserPillIsAFractionOfTheColumnNotTheWindow() throws {
    // omi-test-quality: source-inspection -- static layout tripwire. The bug it
    // guards is invisible to a unit test because it lives in which *container*
    // a modifier resolves against: `containerRelativeFrame` resolves to the
    // ScrollView, so once the scroll view spans the shell the pill became 75%
    // of the whole window instead of 75% of the message column.
    let source = try sourceFile("Sources/MainWindow/Components/ChatBubble.swift")
    let policy = try XCTUnwrap(
      source.components(separatedBy: "private struct ChatBubbleColumnWidth").last
    )
    XCTAssertFalse(
      policy.contains("containerRelativeFrame"),
      "the pill must size against the row it is in, not the scroll view"
    )
    XCTAssertTrue(policy.contains("ChatBubbleLayout.userWidthFraction"))
  }

  func testTheColumnCapLandsOnTheRowsNotTheScrollView() throws {
    // omi-test-quality: source-inspection -- static layout tripwire.
    let source = try sourceFile("Sources/MainWindow/Components/ChatMessagesView.swift")
    XCTAssertTrue(
      source.contains(".frame(maxWidth: contentColumnWidth ?? .infinity)"),
      "the readable cap belongs to the column"
    )

    let home = try sourceFile("Sources/MainWindow/Pages/DashboardPage.swift")
    XCTAssertTrue(home.contains("contentColumnWidth: width"))
    XCTAssertFalse(
      home.contains("// Chat is the Home surface itself")
        && home.contains(".frame(width: width)\n  }"),
      "framing the whole transcript narrows the scroll view and moves the scroller inside the shell"
    )
  }

  // MARK: - Fade bands

  func testTheTranscriptFadeIsFixedNotFractional() throws {
    // omi-test-quality: source-inspection -- static layout tripwire.
    //
    // The mask lives in ChatMessagesView, not on the caller. Masking the whole
    // view from outside also masked the jump-to-latest chip, which sits at the
    // bottom edge where the mask goes to zero — so the one control for getting
    // back to the live edge faded out exactly as it appeared.
    let transcript = try sourceFile("Sources/MainWindow/Components/ChatMessagesView.swift")
    let mask = try XCTUnwrap(
      transcript.components(separatedBy: "private var transcriptMask").last
    )

    XCTAssertTrue(mask.contains("transcriptFadeHeight"))
    // A `location:` stop is a fraction of the masked height, which is what made
    // the band breathe as the composer grew.
    XCTAssertFalse(
      mask.contains("location:"),
      "fractional stops re-scale the fade whenever the panel resizes"
    )
    // Everything below the composer's top edge is masked out, because the
    // composer fill is translucent and text behind it would read through.
    XCTAssertTrue(mask.contains("composerCoverHeight"))

    let body = try XCTUnwrap(transcript.components(separatedBy: "var body: some View {").last)
    let stack = try XCTUnwrap(body.components(separatedBy: "private var transcriptMask").first)
    XCTAssertTrue(
      stack.contains("scrollContent(proxy: proxy)\n          .mask(transcriptMask)"),
      "the mask belongs to the transcript, not to the stack that also holds the jump chip"
    )
  }

  func testTheTranscriptReservesRoomForTheFloatingComposer() throws {
    // omi-test-quality: source-inspection -- static layout tripwire. Without the
    // inset the last row can never be scrolled clear of the bar covering it.
    let home = try sourceFile("Sources/MainWindow/Pages/DashboardPage.swift")
    XCTAssertTrue(
      home.contains("bottomContentInset: homeComposerHeight + Self.homeTranscriptBottomFade"),
      "the reserved inset must cover the composer and the band above it"
    )
  }

  // MARK: - Helpers

  private func sourceFile(_ relativePath: String) throws -> String {
    let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourceURL = testsURL.deletingLastPathComponent().appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
