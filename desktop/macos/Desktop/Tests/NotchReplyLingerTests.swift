import XCTest

@testable import Omi_Computer

/// The notch reply linger: how long Omi's spoken answer stays readable after
/// the turn ends, and what takes it away.
@MainActor
final class NotchReplyLingerTests: XCTestCase {
  /// A model whose countdown only elapses when the test says so.
  private func makeModel() -> (NotchReplyLingerModel, () -> Void) {
    var resume: (() -> Void)?
    let model = NotchReplyLingerModel(sleep: { _ in
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        resume = { continuation.resume() }
      }
    })
    return (model, { resume?() })
  }

  func testAnEmptyReplyNeverLingers() {
    let (model, _) = makeModel()
    model.noteReply("")
    model.beginReplyDismiss()
    XCTAssertFalse(model.isLingeringReply)
  }

  func testReplyCapturedDuringStreamingIsLingeringTheInstantTheTurnEnds() {
    // Captured mid-stream on purpose: waiting until the turn ends leaves one
    // frame where nothing is held and the surface collapses to idle.
    let (model, _) = makeModel()
    model.noteReply("The meeting moved to Thursday.")
    XCTAssertTrue(model.isLingeringReply)

    model.beginReplyDismiss()
    XCTAssertTrue(model.isLingeringReply)
  }

  func testHoldElapsingDismissesTheReply() async {
    let (model, elapse) = makeModel()
    model.noteReply("The meeting moved to Thursday.")
    model.beginReplyDismiss()
    await Task.yield()  // let the countdown reach its sleep

    elapse()
    await settle()

    XCTAssertFalse(model.isLingeringReply)
  }

  func testHoverKeepsTheReplyUntilThePointerLeaves() async {
    let (model, elapse) = makeModel()
    model.noteReply("A long answer worth reading twice.")
    model.beginReplyDismiss()
    await Task.yield()

    // Pointer lands on the notch: the pending countdown is cancelled, so the
    // original hold elapsing must not take the reply away.
    model.keepReply()
    elapse()
    await settle()
    XCTAssertTrue(model.isLingeringReply)

    model.resumeReplyDismiss()
    await Task.yield()
    elapse()
    await settle()
    XCTAssertFalse(model.isLingeringReply)
  }

  private func settle() async {
    for _ in 0..<5 { await Task.yield() }
  }

  func testEscapeDismissesImmediately() {
    let (model, _) = makeModel()
    model.noteReply("The meeting moved to Thursday.")
    model.beginReplyDismiss()

    model.dismissReply()
    XCTAssertFalse(model.isLingeringReply)
  }

  func testANewTurnClearsTheDismissedFlagSoTheNextReplyCanLinger() {
    let (model, _) = makeModel()
    model.noteReply("First answer.")
    model.dismissReply()
    XCTAssertFalse(model.isLingeringReply)

    model.resetReply()
    model.noteReply("Second answer.")
    XCTAssertTrue(model.isLingeringReply)
    XCTAssertEqual(model.heldReply, "Second answer.")
  }
}

/// Pacing of the reply reveal — it follows the spoken voice, not the token
/// stream, and never shows a half-typed word.
@MainActor
final class ReplyRevealModelTests: XCTestCase {
  func testFirstFrameShowsTheOpeningWordSoTheRevealStartsWithTheAudio() {
    let model = ReplyRevealModel()
    let start = Date()
    XCTAssertEqual(model.revealed(at: start, full: "Hello there friend"), "Hello")
  }

  func testRevealOnlyEverEndsOnAWholeWord() {
    let model = ReplyRevealModel()
    let start = Date()
    _ = model.revealed(at: start, full: "Hello there friend")
    // Half a second in, at 20 chars/sec, lands mid-word; the tail is trimmed.
    let shown = model.revealed(at: start.addingTimeInterval(0.5), full: "Hello there friend")
    XCTAssertFalse(shown.hasSuffix(" "))
    XCTAssertTrue("Hello there friend".hasPrefix(shown))
  }

  func testRevealCompletesToTheFullTextRatherThanSnapping() {
    let model = ReplyRevealModel()
    let start = Date()
    _ = model.revealed(at: start, full: "Hello there friend")
    // Well past the time needed for 18 characters at 20 chars/sec.
    var shown = ""
    for step in 1...20 {
      shown = model.revealed(
        at: start.addingTimeInterval(0.1 * Double(step)), full: "Hello there friend")
    }
    XCTAssertEqual(shown, "Hello there friend")
  }

  func testAShorterBufferRestartsTheRevealForANewTurn() {
    let model = ReplyRevealModel()
    let start = Date()
    _ = model.revealed(at: start, full: "A long first answer that ran on")
    for step in 1...20 {
      _ = model.revealed(
        at: start.addingTimeInterval(0.1 * Double(step)), full: "A long first answer that ran on")
    }

    // New turn: a shorter buffer must not show the previous reply's tail.
    let shown = model.revealed(at: start.addingTimeInterval(3), full: "Short reply")
    XCTAssertTrue("Short reply".hasPrefix(shown))
  }
}
