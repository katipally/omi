import XCTest

@testable import Omi_Computer

/// Covers the paced reveal that decouples what the transcript shows from when
/// tokens arrive.
///
/// `ChatStreamingBuffer` flushes every 35ms carrying however many characters
/// happened to land, so rendering flushes directly grew the transcript in uneven
/// steps and the follow scroll could only ever be as smooth as the height it was
/// chasing. The reveal approaches the buffer exponentially instead.
@MainActor
final class ChatStreamingRevealTests: XCTestCase {

  private func clock(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: 1_000 + seconds)
  }

  // MARK: - Character granularity

  func testPrefixRevealsPartOfAWordSoGrowthIsContinuous() {
    // Cutting at word boundaries made the text arrive a word at a time, which
    // is a step, not a stream: each step could wrap a line and jolt the height.
    XCTAssertEqual(ChatRevealModel.prefix(of: "hello there world", characters: 14), "hello there wo")
  }

  func testPrefixLeavesFullyRevealedTextUntouched() {
    let text = "hello there world"
    XCTAssertEqual(ChatRevealModel.prefix(of: text, characters: text.count), text)
    XCTAssertEqual(ChatRevealModel.prefix(of: text, characters: text.count + 50), text)
  }

  func testPrefixBreaksOnNewlinesNotOnlySpaces() {
    // Markdown replies are mostly newline-separated, so a space-only rule left
    // list items and headings half-drawn between flushes.
    XCTAssertEqual(ChatRevealModel.prefix(of: "- one\n- two", characters: 8), "- one")
  }

  func testALineShowingOnlyItsMarkerIsHeldBack() {
    // A bare "-" or "##" renders as an empty list item or heading for a frame.
    XCTAssertEqual(ChatRevealModel.prefix(of: "intro\n## Heading here", characters: 9), "intro")
    XCTAssertEqual(ChatRevealModel.prefix(of: "intro\n1. First item", characters: 9), "intro")
    XCTAssertEqual(ChatRevealModel.prefix(of: "- first item here", characters: 2), "")
  }

  func testALineWithARealWordAfterItsMarkerIsShown() {
    XCTAssertEqual(
      ChatRevealModel.prefix(of: "intro\n- first item", characters: 15),
      "intro\n- first i"
    )
  }

  func testPrefixOfAnUnbrokenRunFallsBackToTheRawPrefix() {
    // A long URL has no break to cut at; showing nothing would stall the reveal.
    XCTAssertEqual(
      ChatRevealModel.prefix(of: "https://example.com/very/long", characters: 12),
      "https://exam"
    )
  }

  // MARK: - Unclosed inline markdown

  func testAnUnclosedBoldMarkerIsHeldBackRatherThanDrawnAsAsterisks() {
    // Revealed a character at a time, "**bol" would sit on screen as literal
    // asterisks for several frames and then snap into bold.
    XCTAssertEqual(ChatRevealModel.prefix(of: "we found **three** items", characters: 14), "we found ")
  }

  func testAClosedBoldMarkerRevealsNormally() {
    XCTAssertEqual(
      ChatRevealModel.prefix(of: "we found **three** items", characters: 21),
      "we found **three** it"
    )
  }

  func testAnUnclosedInlineCodeSpanIsHeldBack() {
    XCTAssertEqual(ChatRevealModel.prefix(of: "run `make setup` first", characters: 9), "run ")
  }

  func testAHalfWrittenLinkIsHeldBackUntilItsTargetCloses() {
    let full = "see [the guide](https://omi.me) for more"
    XCTAssertEqual(ChatRevealModel.prefix(of: full, characters: 24), "see ")
    XCTAssertEqual(ChatRevealModel.prefix(of: full, characters: 34), "see [the guide](https://omi.me) fo")
  }

  func testABulletIsNotMistakenForOpenEmphasis() {
    // "* item" opens a list, not italics — holding it back would stall every
    // asterisk-style list for as long as the item took to arrive.
    XCTAssertEqual(ChatRevealModel.prefix(of: "intro\n* first item", characters: 13), "intro\n* first")
  }

  func testUnderscoresInIdentifiersAreNotTreatedAsEmphasis() {
    XCTAssertEqual(
      ChatRevealModel.prefix(of: "call record_fallback here", characters: 18),
      "call record_fallba"
    )
  }

  // MARK: - Pacing

  func testAFreshModelIsNotCompleteBeforeItHasSeenAnyText() {
    // `revealed` and `lastFullCount` both start at zero, so a bare `>=` reported
    // a brand-new turn as already finished. The view stops its clock on
    // `isComplete`, so the reveal never started and every flush of every reply
    // rendered raw — the pacing existed but was unreachable.
    XCTAssertFalse(ChatRevealModel().isComplete)
  }

  func testTheFirstFlushOfATurnStartsThePacedReveal() {
    let model = ChatRevealModel()
    let flush = "A fairly long first flush of an arriving reply"
    XCTAssertLessThan(model.revealed(at: clock(0), full: flush).count, flush.count)
    XCTAssertFalse(model.isComplete)
  }

  func testFirstFrameShowsTheOpeningWordRatherThanABlankBeat() {
    let model = ChatRevealModel()
    XCTAssertEqual(model.revealed(at: clock(0), full: "Reading your screen now"), "Reading")
  }

  func testRevealIsMonotonicAndNeverOvershootsTheBuffer() {
    let model = ChatRevealModel()
    let full = String(repeating: "word ", count: 400)
    var previous = 0
    for step in 0...40 {
      let shown = model.revealed(at: clock(Double(step) * 0.033), full: full).count
      XCTAssertGreaterThanOrEqual(shown, previous, "reveal went backwards at step \(step)")
      XCTAssertLessThanOrEqual(shown, full.count)
      previous = shown
    }
  }

  func testABurstDrainsWithoutSnappingInOneFrame() {
    let model = ChatRevealModel()
    let full = String(repeating: "word ", count: 800)  // 4000 characters at once
    _ = model.revealed(at: clock(0), full: full)
    let afterOneFrame = model.revealed(at: clock(0.033), full: full).count

    XCTAssertGreaterThan(afterOneFrame, 0, "the reveal must move on every frame")
    XCTAssertLessThan(
      afterOneFrame, full.count,
      "a burst must drain over several frames, never land in one"
    )
    XCTAssertFalse(model.isComplete)
  }

  func testTheRevealCatchesUpAndCompletesAfterTheStreamStops() {
    let model = ChatRevealModel()
    let full = String(repeating: "word ", count: 800)
    var t = 0.0
    // Frames with no new text arriving: the backlog must fully drain, or a
    // finished reply would sit truncated on screen.
    while t < 8.0 {
      _ = model.revealed(at: clock(t), full: full, isStreaming: false)
      t += 0.033
    }
    XCTAssertTrue(model.isComplete)
    XCTAssertEqual(model.revealed(at: clock(t), full: full, isStreaming: false), full)
  }

  func testTheTailDrainsFasterOnceTheStreamHasEnded() {
    // Text still crawling after omi has visibly finished reads as a stall, so
    // the ceiling lifts when there are no more tokens to keep pace with.
    let full = String(repeating: "word ", count: 800)

    func revealedAfterOneSecond(isStreaming: Bool) -> Int {
      let model = ChatRevealModel()
      var t = 0.0
      while t < 1.0 {
        _ = model.revealed(at: clock(t), full: full, isStreaming: isStreaming)
        t += 0.033
      }
      return model.revealed(at: clock(t), full: full, isStreaming: isStreaming).count
    }

    XCTAssertGreaterThan(
      revealedAfterOneSecond(isStreaming: false),
      revealedAfterOneSecond(isStreaming: true)
    )
  }

  func testTheRevealNeverOutrunsAModelsOwnOutputRate() {
    // The cap is the whole difference between text that appears and text that
    // is written: uncapped, the catch-up term alone reaches thousands of
    // characters a second on any real reply.
    let model = ChatRevealModel()
    let full = String(repeating: "word ", count: 2000)
    _ = model.revealed(at: clock(0), full: full)
    let shown = model.revealed(at: clock(0.1), full: full).count
    XCTAssertLessThanOrEqual(
      Double(shown), ChatRevealModel.streamingCharsPerSecond * 0.1 + 10
    )
  }

  func testFinishRevealsEverythingWithoutAnimating() {
    // Saved history and completed replies are whole on first render; without
    // this every message would replay its reveal on scroll-in.
    let model = ChatRevealModel()
    let full = "A reply that was already complete when it first rendered."
    model.finish(full: full)
    XCTAssertTrue(model.isComplete)
    XCTAssertEqual(model.revealed(at: clock(0), full: full), full)
  }

  func testANewTurnRestartsTheReveal() {
    let model = ChatRevealModel()
    let first = String(repeating: "word ", count: 200)
    model.finish(full: first)
    XCTAssertTrue(model.isComplete)

    // A shorter buffer is a new turn, not a truncation of the old one.
    let second = "Fresh reply starting over"
    let shown = model.revealed(at: clock(1), full: second)
    XCTAssertLessThan(shown.count, second.count)
    XCTAssertFalse(model.isComplete)
  }

  func testALongStallCannotDumpTheWholeBufferAtOnce() {
    // dt is clamped, so an app that was descheduled for a second still resumes
    // by gliding rather than by teleporting to the end.
    let model = ChatRevealModel()
    let full = String(repeating: "word ", count: 2000)
    _ = model.revealed(at: clock(0), full: full)
    let afterStall = model.revealed(at: clock(5.0), full: full).count
    XCTAssertLessThan(afterStall, full.count)
  }
}
