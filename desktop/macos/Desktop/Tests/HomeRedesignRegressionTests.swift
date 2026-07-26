import XCTest

@testable import Omi_Computer

/// Regressions from the chat-as-home redesign (#10184) and the floating-bar
/// typing removal (#10181).
final class HomeStageCollapseCatcherTests: XCTestCase {
  func testHubNeverGetsACatcher() {
    // The hub is the base surface, never an overlay. A catcher over it would
    // invert the gesture: a stray click or Esc would *open* the chat.
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .hub, resting: .hub))
  }

  func testEverySurfaceOverTheHubCollapsesBackToIt() {
    XCTAssertTrue(HomeStageMode.collapseCatcherActive(mode: .chat, resting: .hub))
    XCTAssertTrue(HomeStageMode.collapseCatcherActive(mode: .connect, resting: .hub))
  }
}

/// Home has exactly one empty state. It used to have three — a landing hero on
/// first open, the hub after that, and a third hero inside an empty transcript —
/// which meant "Home with nothing to show" looked like three different products
/// depending on how you got there.
final class HomeStageSurfacePolicyTests: XCTestCase {
  func testHubIsBothWhereHomeOpensAndWhereEverythingCollapsesTo() {
    // One answer, no session state: nothing can remember a *different* front
    // door and disagree with the collapse target.
    XCTAssertEqual(HomeHistoryPresentationPolicy.openingMode, .hub)
    XCTAssertEqual(HomeHistoryPresentationPolicy.restingMode, .hub)
  }

  func testHistoryNeverAutoRevealsItself() {
    // The transcript lives above the hub and is reached deliberately — scroll
    // or send. An async history load must not yank the surface out from under
    // someone reading the hub.
    XCTAssertEqual(HomeHistoryPresentationPolicy.openingMode, .hub)
  }

  func testEverySurfaceReportsItselfToAutomation() {
    XCTAssertEqual(HomeStageMode.hub.automationLabel, "hub")
    XCTAssertEqual(HomeStageMode.chat.automationLabel, "chat")
    XCTAssertEqual(HomeStageMode.connect.automationLabel, "connect")
  }

  func testOnlyTheHubTakesTheStageTopBias() {
    XCTAssertEqual(HomeStageMode.hub.topPadding(hub: 8), 8)
    XCTAssertEqual(HomeStageMode.chat.topPadding(hub: 8), 0)
  }
}

@MainActor
final class HomeChatRevealMonitorTests: XCTestCase {
  func testTrackpadJitterDoesNotLeaveTheHub() {
    XCTAssertFalse(HomeChatRevealMonitor.isDeliberateScroll(deltaY: 0))
    XCTAssertFalse(HomeChatRevealMonitor.isDeliberateScroll(deltaY: 3))
  }

  func testADeliberateScrollInEitherDirectionReveals() {
    XCTAssertTrue(HomeChatRevealMonitor.isDeliberateScroll(deltaY: 12))
    XCTAssertTrue(HomeChatRevealMonitor.isDeliberateScroll(deltaY: -12))
  }

  func testStartAndStopAreIdempotent() {
    // Two owners call stop (the hub's onDisappear and the page's), and an
    // app-global event monitor that outlives the hub fires on every scroll
    // anywhere in the app.
    let monitor = HomeChatRevealMonitor()
    monitor.start(shouldReveal: { false }, onReveal: {})
    monitor.start(shouldReveal: { false }, onReveal: {})
    XCTAssertTrue(monitor.isRunning)
    monitor.stop()
    monitor.stop()
    XCTAssertFalse(monitor.isRunning)
  }
}

@MainActor
final class MainChatNavigationRequestStoreTests: XCTestCase {
  func testRequestIsConsumedExactlyOnce() {
    let store = MainChatNavigationRequestStore.shared
    _ = store.consume()  // clear any pending state from other tests

    XCTAssertFalse(store.consume())

    store.request()
    XCTAssertTrue(store.isPending)
    XCTAssertTrue(store.consume())
    XCTAssertFalse(store.consume())
  }

  func testRequestPostsOpenMainChatNotification() {
    let store = MainChatNavigationRequestStore.shared
    _ = store.consume()

    let expectation = expectation(
      forNotification: .openMainChatRequested, object: nil, notificationCenter: .default)
    store.request()
    wait(for: [expectation], timeout: 1)
    _ = store.consume()
  }
}

final class ChatBubbleMetadataRevealTests: XCTestCase {
  func testKeyboardFocusAloneRevealsMetadataRow() {
    // Regression: the quiet-timeline redesign gated the row on pointer hover
    // only, leaving Tab / Full Keyboard Access focused on invisible buttons.
    XCTAssertTrue(
      ChatBubbleMetadataReveal.isVisible(hovering: false, controlFocused: true, transientFeedback: false))
  }

  func testHiddenOnlyWhenNeitherHoveredNorFocusedNorMidInteraction() {
    XCTAssertFalse(
      ChatBubbleMetadataReveal.isVisible(hovering: false, controlFocused: false, transientFeedback: false))
    XCTAssertTrue(
      ChatBubbleMetadataReveal.isVisible(hovering: true, controlFocused: false, transientFeedback: false))
    XCTAssertTrue(
      ChatBubbleMetadataReveal.isVisible(hovering: false, controlFocused: false, transientFeedback: true))
  }
}
