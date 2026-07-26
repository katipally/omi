import XCTest

@testable import Omi_Computer

/// The reply reveal paces Omi's answer to the speaking cadence. `isComplete` is
/// what stops its per-frame clock: the previous duration estimate could be
/// outrun by the clamped per-frame step, freezing the reply mid-sentence.
@MainActor
final class NotchReplyRevealTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 1_000)

  private func advance(_ model: ReplyRevealModel, _ text: String, by seconds: TimeInterval) -> String {
    // The model clamps each step to 0.1s, so walk the clock in real frames.
    var shown = model.revealed(at: start, full: text)
    var elapsed: TimeInterval = 0
    while elapsed < seconds {
      elapsed += 0.05
      shown = model.revealed(at: start.addingTimeInterval(elapsed), full: text)
    }
    return shown
  }

  func testFirstFrameShowsTheOpeningWordAndIsNotYetComplete() {
    let model = ReplyRevealModel()

    XCTAssertEqual(model.revealed(at: start, full: "hello there friend"), "hello")
    XCTAssertFalse(model.isComplete)
  }

  func testNeverRevealsAHalfTypedWord() {
    let text = "extraordinarily complicated reply"

    for step in stride(from: 0.0, through: 2.0, by: 0.05) {
      let shown = advance(ReplyRevealModel(), text, by: step)
      XCTAssertTrue(
        shown.isEmpty || text.hasPrefix(shown), "\(shown) is not a prefix of the reply")
      guard shown != text else { continue }
      let next = text.dropFirst(shown.count).first
      XCTAssertTrue(next == nil || next == " ", "reveal stopped mid-word at \"\(shown)\"")
    }
  }

  func testCompletesOnceTheRevealCatchesUpWithTheBuffer() {
    let model = ReplyRevealModel()
    let text = "a short reply"

    XCTAssertEqual(advance(model, text, by: 3), text)
    XCTAssertTrue(model.isComplete)
  }

  /// A model that has never rendered a frame must not report itself finished,
  /// or the timeline pauses before the first word is ever drawn.
  func testFreshModelIsNotComplete() {
    XCTAssertFalse(ReplyRevealModel().isComplete)
  }

  func testShrinkingBufferRestartsTheReveal() {
    let model = ReplyRevealModel()
    XCTAssertEqual(advance(model, "the first turn reply text", by: 3), "the first turn reply text")
    XCTAssertTrue(model.isComplete)

    // A new turn: a shorter buffer restarts the reveal from its opening word.
    XCTAssertEqual(model.revealed(at: start.addingTimeInterval(4), full: "new turn"), "new")
    XCTAssertFalse(model.isComplete)
  }
}
