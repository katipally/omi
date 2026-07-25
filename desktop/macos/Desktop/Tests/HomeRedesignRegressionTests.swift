import XCTest

@testable import Omi_Computer

/// Regressions from the chat-as-home redesign (#10184) and the floating-bar
/// typing removal (#10181).
final class HomeStageCollapseCatcherTests: XCTestCase {
  func testChatWithHistoryIsRestingSoNoCatcherMounts() {
    // Chat with history is Home itself: no click-outside / Esc catcher.
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .chat, resting: .chat))
  }

  func testHubNeverGetsACatcherEvenWhenChatIsResting() {
    // Regression: with history present the hub differs from the resting mode,
    // which used to mount the catchers over the hub — a stray click or Esc
    // then *opened* the chat instead of leaving the user on the hub.
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .hub, resting: .chat))
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .hub, resting: .hub))
  }

  func testNonRestingPanelsStillCollapse() {
    // Empty-history chat and the connect tray remain escapable overlays.
    XCTAssertTrue(HomeStageMode.collapseCatcherActive(mode: .chat, resting: .hub))
    XCTAssertTrue(HomeStageMode.collapseCatcherActive(mode: .connect, resting: .hub))
    XCTAssertTrue(HomeStageMode.collapseCatcherActive(mode: .connect, resting: .chat))
  }

  func testLandingNeverGetsACatcherLikeTheHub() {
    // The landing is a base surface, not an overlay. A catcher over it would
    // invert the gesture: a stray click or Esc would *open* the chat.
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .landing, resting: .chat))
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .landing, resting: .hub))
    XCTAssertFalse(HomeStageMode.collapseCatcherActive(mode: .landing, resting: .landing))
  }
}

final class HomeStageLandingPresentationTests: XCTestCase {
  func testLandingReportsItselfToAutomation() {
    // `omi-ctl state` distinguishes the landing from the hub, so a run can
    // assert Home actually opened on the landing rather than skipping it.
    XCTAssertEqual(HomeStageMode.landing.automationLabel, "landing")
    XCTAssertEqual(HomeStageMode.hub.automationLabel, "hub")
    XCTAssertEqual(HomeStageMode.chat.automationLabel, "chat")
    XCTAssertEqual(HomeStageMode.connect.automationLabel, "connect")
  }

  func testLandingCentersItselfInsteadOfTakingTheHubTopBias() {
    // The landing is vertically centered by its own spacers; inheriting the
    // hub's top padding would push the hero off-center.
    XCTAssertEqual(HomeStageMode.landing.topPadding(hub: 8), 0)
    XCTAssertEqual(HomeStageMode.hub.topPadding(hub: 8), 8)
    XCTAssertEqual(HomeStageMode.chat.topPadding(hub: 8), 0)
  }
}

final class HomeHistoryPresentationPolicyTests: XCTestCase {
  func testInitialHistoryLoadKeepsUsefulHubVisible() {
    XCTAssertEqual(
      HomeHistoryPresentationPolicy.restingMode(isLoading: true, messageCount: 0),
      .hub)
    XCTAssertEqual(
      HomeHistoryPresentationPolicy.restingMode(isLoading: true, messageCount: 12),
      .hub)
  }

  func testCompletedHistoryLoadMakesChatTheRestingSurface() {
    XCTAssertEqual(
      HomeHistoryPresentationPolicy.restingMode(isLoading: false, messageCount: 12),
      .chat)
  }

  func testCompletedEmptyLoadKeepsNewUserHubVisible() {
    XCTAssertEqual(
      HomeHistoryPresentationPolicy.restingMode(isLoading: false, messageCount: 0),
      .hub)
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
