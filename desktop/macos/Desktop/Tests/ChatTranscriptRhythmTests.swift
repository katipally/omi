import XCTest

@testable import Omi_Computer

/// Covers the two pure rules the reworked transcript depends on: the gap that
/// separates one turn from the next, and the status line shown while omi works.
///
/// Both used to be implicit in the view. Row gaps came from a single
/// `LazyVStack` spacing, so a question and its answer sat as far apart as two
/// unrelated exchanges; the wait was carried by a spinning per-message avatar
/// that the plain-text rework removed.
final class ChatTranscriptRhythmTests: XCTestCase {

  // MARK: - Turn spacing

  func testFirstRowGetsNoLeadingGap() {
    XCTAssertEqual(ChatTurnSpacing.leadingGap(previous: nil, current: .ai), 0)
    XCTAssertEqual(ChatTurnSpacing.leadingGap(previous: nil, current: .user), 0)
  }

  func testUserMessageAfterOmiOpensANewTurn() {
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .ai, current: .user),
      ChatTurnSpacing.betweenTurns
    )
  }

  func testOmiReplyStaysInsideTheTurnItAnswers() {
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .user, current: .ai),
      ChatTurnSpacing.withinTurn
    )
  }

  func testConsecutiveMessagesFromOneSenderStayInsideTheTurn() {
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .user, current: .user),
      ChatTurnSpacing.withinTurn
    )
    XCTAssertEqual(
      ChatTurnSpacing.leadingGap(previous: .ai, current: .ai),
      ChatTurnSpacing.withinTurn
    )
  }

  func testTurnBoundaryIsWiderThanTheGapInsideATurn() {
    XCTAssertGreaterThan(ChatTurnSpacing.betweenTurns, ChatTurnSpacing.withinTurn)
  }

  // MARK: - Working status

  private func aiMessage(blocks: [ChatContentBlock]) -> ChatMessage {
    ChatMessage(text: "", sender: .ai, isStreaming: true, contentBlocks: blocks)
  }

  private func toolCall(_ name: String, _ status: ToolCallStatus) -> ChatContentBlock {
    .toolCall(id: name, name: name, status: status)
  }

  func testNoMessageYetReadsAsThinking() {
    XCTAssertEqual(ChatWorkingStatus.label(for: nil), ChatWorkingStatus.idleLabel)
  }

  func testAwaitingOmiAfterTheUserSendsReadsAsThinking() {
    // The user's row is the last message until omi's own row arrives.
    let sent = ChatMessage(text: "what are we doing", sender: .user)
    XCTAssertEqual(ChatWorkingStatus.label(for: sent), ChatWorkingStatus.idleLabel)
  }

  func testReplyWithNoToolsReadsAsThinking() {
    let message = aiMessage(blocks: [.text(id: "t", text: "Not much yet")])
    XCTAssertEqual(ChatWorkingStatus.label(for: message), ChatWorkingStatus.idleLabel)
  }

  func testInFlightToolNamesItself() {
    let message = aiMessage(blocks: [toolCall("WebFetch: https://example.com", .running)])
    XCTAssertEqual(ChatWorkingStatus.label(for: message), "Fetching page")
  }

  func testTheMostRecentInFlightToolWins() {
    let message = aiMessage(blocks: [
      toolCall("first", .completed),
      toolCall("WebFetch: https://example.com", .running),
    ])
    XCTAssertEqual(ChatWorkingStatus.label(for: message), "Fetching page")
  }

  // MARK: - Streaming scroll

  func testTheFollowKeepsRunningAfterTheStreamEnds() {
    // The reveal is paced independently of token arrival, so the transcript is
    // still growing after the last token lands.
    XCTAssertGreaterThan(ChatStreamScroll.settleTail, 0)
  }

  // MARK: - Damped live-edge follow

  func testAWrapIsAbsorbedGraduallyRatherThanInOneFrame() {
    // The failure this replaces: a commanded scroll assigns the offset, so a
    // line wrap moved every line on screen by a full line height in one frame.
    let oneLine: CGFloat = 20
    let afterAFrame = ChatLiveEdgeFollower.stepped(from: 0, toward: oneLine, dt: 1.0 / 60)
    XCTAssertGreaterThan(afterAFrame, 0, "the follow must move on every frame")
    XCTAssertLessThan(afterAFrame, oneLine / 2, "and must not land the whole wrap at once")
  }

  func testTheFollowConvergesAndNeverOvershoots() {
    let target: CGFloat = 240
    var offset: CGFloat = 0
    for _ in 0..<60 {
      let next = ChatLiveEdgeFollower.stepped(from: offset, toward: target, dt: 1.0 / 60)
      XCTAssertGreaterThanOrEqual(next, offset, "the follow must never move backwards")
      XCTAssertLessThanOrEqual(next, target, "and must never pass the live edge")
      offset = next
    }
    XCTAssertEqual(offset, target, accuracy: ChatLiveEdgeFollower.snapThreshold)
  }

  func testTheLastFractionOfAPointSnapsInsteadOfCreeping() {
    // Left un-snapped the transcript parks a hair off the live edge, which the
    // at-bottom test then reads as the reader having scrolled away.
    let almost = 100 - ChatLiveEdgeFollower.snapThreshold / 2
    XCTAssertEqual(ChatLiveEdgeFollower.stepped(from: almost, toward: 100, dt: 1.0 / 60), 100)
  }

  func testALongStallResumesByGlidingNotTeleporting() {
    // An app descheduled for a second must not dump the accumulated distance
    // into the frame it wakes up on.
    let stepped = ChatLiveEdgeFollower.stepped(from: 0, toward: 1000, dt: 5)
    XCTAssertLessThan(stepped, 1000)
  }

  // MARK: - Working motion

  func testReadingAndSearchingToolsCondense() {
    for tool in [
      "Read", "Grep", "Glob", "WebSearch", "WebFetch",
      "execute_sql", "semantic_search", "search_tasks",
      "Read: /tmp/a.swift", "WebSearch: \"omi\"",
    ] {
      XCTAssertEqual(ChatMarkMotion.forTool(tool), .gather, "\(tool) should gather")
    }
  }

  func testWritingAndExecutingToolsUnspool() {
    for tool in [
      "Write", "Edit", "MultiEdit", "NotebookEdit", "Bash",
      "spawn_agent", "run_agent_and_wait", "send_agent_message",
      "Bash: git status", "Edit: /tmp/a.swift",
    ] {
      XCTAssertEqual(ChatMarkMotion.forTool(tool), .wave, "\(tool) should unspool")
    }
  }

  func testMCPPrefixIsStrippedBeforeClassifying() {
    XCTAssertEqual(ChatMarkMotion.forTool("mcp__omi-tools__execute_sql"), .gather)
    XCTAssertEqual(ChatMarkMotion.forTool("mcp__omi-tools__spawn_agent"), .wave)
  }

  func testUnknownToolTakesTheQuieterMotion() {
    // An unrecognized tool must not get the loud unspooling motion on a guess.
    XCTAssertEqual(ChatMarkMotion.forTool("some_future_tool"), .gather)
  }

  func testPlainThinkingCondenses() {
    XCTAssertEqual(ChatWorkingStatus.motion(for: nil), .gather)
    XCTAssertEqual(
      ChatWorkingStatus.motion(for: aiMessage(blocks: [.text(id: "t", text: "hi")])),
      .gather
    )
  }

  func testMotionFollowsTheInFlightTool() {
    let writing = aiMessage(blocks: [
      toolCall("Read", .completed),
      toolCall("Write", .running),
    ])
    XCTAssertEqual(ChatWorkingStatus.motion(for: writing), .wave)

    let reading = aiMessage(blocks: [
      toolCall("Write", .completed),
      toolCall("Read", .running),
    ])
    XCTAssertEqual(ChatWorkingStatus.motion(for: reading), .gather)
  }

  func testBothMotionsShareTheRingAsTheirBoundary() {
    // The model may only swap motions at a cycle wrap. That is safe precisely
    // because both motions begin and end on the full ring — if one ever started
    // mid-shape, the swap would cut the mark in half.
    XCTAssertGreaterThan(ChatMarkMotion.gather.cycle, 0)
    XCTAssertGreaterThan(ChatMarkMotion.wave.cycle, 0)
    XCTAssertNotEqual(ChatMarkMotion.gather.cycle, ChatMarkMotion.wave.cycle)
  }

  func testFinishedToolsFallBackToThinking() {
    // Every step is done but the turn is still open, so the reply is being
    // composed rather than a tool still running.
    let message = aiMessage(blocks: [
      toolCall("WebFetch: https://example.com", .completed),
      toolCall("second", .completed),
    ])
    XCTAssertEqual(ChatWorkingStatus.label(for: message), ChatWorkingStatus.idleLabel)
  }
}
