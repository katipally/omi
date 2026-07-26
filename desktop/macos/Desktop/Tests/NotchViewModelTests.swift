import AppKit
import XCTest

@testable import Omi_Computer

/// Hand-cranked stand-in for the linger's wall clock. A hold parks until the
/// test advances past it and observes cancellation the way `Task.sleep` does,
/// which is the behaviour the pause relies on. No wall-clock time is ever spent,
/// so the state machine is exercised at exactly the transitions that matter.
/// Pinned to the main actor so a hold, its release and the assertions that read
/// them all run on one executor — the ordering the test depends on is then a
/// property of the isolation, not of how the scheduler happened to interleave.
@MainActor
private final class LingerClock {
  private(set) var holds: [TimeInterval] = []
  private var elapsed: TimeInterval?

  /// Advance far enough to elapse every hold no longer than `seconds`. A hold
  /// longer than that keeps parking, which is what lets a test tell the short
  /// countdown apart from the ceiling that replaced it.
  func release(upTo seconds: TimeInterval = .infinity) { elapsed = seconds }

  func hold(_ seconds: TimeInterval) async {
    holds.append(seconds)
    while !Task.isCancelled, seconds > (elapsed ?? -1) {
      await Task.yield()
    }
  }
}

/// The notch's sizing authority and its reply-linger state machine.
///
/// The sizing half guards one property above all: the NSPanel frame is fixed at
/// the largest any presentation can need, and measured content resizes only the
/// black surface inside it. Let a measurement reach `windowSize` and the panel
/// grows with the card, at which point an expansion stops looking like it came
/// out of the camera housing and starts looking like a window opening beside it.
@MainActor
final class NotchViewModelTests: XCTestCase {
  private let closed = CGSize(width: 232, height: 38)
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func makeViewModel(
    screenFrame: CGRect? = nil,
    sleep: @escaping (TimeInterval) async -> Void = { _ in }
  ) -> NotchViewModel {
    NotchViewModel(
      displayID: 1,
      screenFrame: screenFrame ?? screen,
      closedNotchSize: closed,
      cameraWidth: 172,
      sleep: sleep
    )
  }

  /// Display heights chosen so the notification term is *not* always the tallest
  /// thing in `maxContentSize`. On a large display `voiceMaxHeight` swamps every
  /// card height, so a window size derived from the measured card would come out
  /// constant anyway and the invariant below could not fail. At 500pt the voice
  /// cap (200) sits between the resting card panel (88) and the capped one
  /// (266), which is exactly where a leaked measurement changes the answer.
  private static let revealingScreenHeights: [CGFloat] = [500, 640, 982]

  private func notificationPanelHeight(forCard card: CGFloat) -> CGFloat {
    closed.height + NotchMetrics.notificationSpacing + card
  }

  // MARK: - Passive surfaces follow their content

  func testUnmeasuredNotificationOpensAtTheRestingHeight() {
    let vm = makeViewModel()

    XCTAssertEqual(
      vm.notificationSize.height,
      notificationPanelHeight(forCard: NotchMetrics.notificationMinHeight),
      "An unmeasured card must open at its floor and grow, never open tall and snap down"
    )
  }

  func testShortCardClampsUpToTheMinimumHeight() {
    let vm = makeViewModel()

    vm.notificationBodyHeight = 8

    XCTAssertEqual(
      vm.notificationSize.height,
      notificationPanelHeight(forCard: NotchMetrics.notificationMinHeight)
    )
  }

  func testCardHeightBetweenTheBoundsIsUsedVerbatim() {
    let vm = makeViewModel()

    vm.notificationBodyHeight = 132

    // The regression: this used to be a constant, so a one-line receipt and a
    // four-line proactive card produced the same panel — dead black under one,
    // clipped copy inside the other.
    XCTAssertEqual(vm.notificationSize.height, notificationPanelHeight(forCard: 132))
  }

  func testLongCardClampsDownToTheMaximumHeight() {
    let vm = makeViewModel()

    vm.notificationBodyHeight = 4_000

    XCTAssertEqual(
      vm.notificationSize.height,
      notificationPanelHeight(forCard: NotchMetrics.notificationMaxHeight)
    )
  }

  func testHintStripFollowsItsTextBetweenTheSameKindOfBounds() {
    let vm = makeViewModel()

    XCTAssertEqual(vm.hintSize.height, closed.height + NotchMetrics.hintRowHeight)

    vm.hintBodyHeight = 4
    XCTAssertEqual(vm.hintSize.height, closed.height + NotchMetrics.hintRowHeight)

    vm.hintBodyHeight = 52
    XCTAssertEqual(vm.hintSize.height, closed.height + 52)

    vm.hintBodyHeight = 4_000
    XCTAssertEqual(vm.hintSize.height, closed.height + NotchMetrics.hintMaxHeight)
  }

  /// The two passive surfaces are mutually exclusive but keep their own
  /// measurements, so a tall card that just left cannot size the hint arriving
  /// behind it.
  func testTheCardAndTheHintDoNotShareAMeasurement() {
    let vm = makeViewModel()

    vm.notificationBodyHeight = 190

    XCTAssertEqual(vm.hintSize.height, closed.height + NotchMetrics.hintRowHeight)
  }

  /// Width is a layout constant, not a consequence of the content: the card
  /// wraps inside a fixed lane, which is what stops a height measurement from
  /// feeding back into the width that produced it.
  func testMeasuredHeightNeverMovesThePassiveSurfaceWidths() {
    let vm = makeViewModel()
    let notificationWidth = vm.notificationSize.width
    let hintWidth = vm.hintSize.width

    for measurement in [CGFloat(0), 40, 200, 4_000] {
      vm.notificationBodyHeight = measurement
      vm.hintBodyHeight = measurement

      XCTAssertEqual(vm.notificationSize.width, notificationWidth)
      XCTAssertEqual(vm.hintSize.width, hintWidth)
    }
  }

  // MARK: - The window never moves

  func testWindowSizeIsIdenticalAcrossEveryPresentation() {
    let vm = makeViewModel()
    let baseline = vm.windowSize

    for presentation in Self.everyPresentation {
      let panel = vm.size(for: presentation)

      XCTAssertEqual(vm.windowSize, baseline)
      XCTAssertLessThanOrEqual(panel.width, baseline.width, "\(presentation) overflows its window")
      XCTAssertLessThanOrEqual(panel.height, baseline.height, "\(presentation) overflows its window")
    }
  }

  /// The regression guard for the fixed frame: measurements size the black
  /// surface and nothing else. If `windowSize` ever starts tracking one, the
  /// NSPanel resizes underneath the expansion and the illusion breaks.
  func testMeasuredContentNeverResizesTheWindow() {
    for height in Self.revealingScreenHeights {
      let frame = CGRect(x: 0, y: 0, width: 1512, height: height)
      let vm = makeViewModel(screenFrame: frame)
      let baseline = vm.windowSize

      for measurement in [CGFloat(0), 12, 96, 400, 4_000] {
        vm.notificationBodyHeight = measurement
        vm.hintBodyHeight = measurement
        vm.voiceBodyHeight = measurement

        XCTAssertEqual(
          vm.windowSize, baseline,
          "a measurement of \(measurement) moved the window on a \(height)pt display"
        )

        for presentation in Self.everyPresentation {
          let panel = vm.size(for: presentation)
          XCTAssertLessThanOrEqual(panel.width, baseline.width)
          XCTAssertLessThanOrEqual(panel.height, baseline.height)
        }
      }
    }
  }

  /// Proves the test above can actually fail. If the window were sized from the
  /// measured card instead of the card's cap, these two would differ on a 500pt
  /// display — so this pins the geometry that makes the invariant observable
  /// rather than vacuously true.
  func testTheWindowInvariantIsObservableOnASmallDisplay() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 500)
    let vm = makeViewModel(screenFrame: frame)

    let restingPanel = notificationPanelHeight(forCard: NotchMetrics.notificationMinHeight)
    let cappedPanel = notificationPanelHeight(forCard: NotchMetrics.notificationMaxHeight)
    XCTAssertLessThan(restingPanel, vm.voiceMaxHeight)
    XCTAssertGreaterThan(cappedPanel, vm.voiceMaxHeight)
  }

  private static let everyPresentation: [NotchPresentation] = [
    .idle, .listening, .thinking, .responding, .hint("Hold longer to record"),
    .notification(UUID()),
  ]

  // MARK: - Reply linger

  func testStreamedTextStartsTheLingerAndBlankTextDoesNot() {
    let vm = makeViewModel()

    vm.noteReply("")
    XCTAssertFalse(vm.isLingeringReply)

    vm.noteReply("Here is the answer")
    XCTAssertTrue(vm.isLingeringReply)
    XCTAssertEqual(vm.heldReply, "Here is the answer")
  }

  func testTheHoldElapsingDismissesTheReply() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })
    vm.noteReply("Here is the answer")

    vm.beginReplyDismiss(hold: 5)
    await settle()
    XCTAssertEqual(clock.holds, [5])
    XCTAssertTrue(vm.isLingeringReply, "the reply must survive until its hold elapses")

    clock.release()
    await settle()
    XCTAssertTrue(vm.replyDismissed)
    XCTAssertFalse(vm.isLingeringReply)
  }

  func testNoCountdownStartsWhenThereIsNothingLingering() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })

    vm.beginReplyDismiss()
    vm.resumeReplyDismiss()
    await settle()

    XCTAssertEqual(clock.holds, [])
  }

  /// Hovering pauses the countdown. The pointer leaving restarts it on a shorter
  /// grace, because the reply has already had its read time.
  func testHoverPausesTheCountdownAndLeavingResumesItOnAShorterGrace() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })
    vm.noteReply("Here is the answer")

    vm.beginReplyDismiss(hold: 5)
    await settle()
    vm.keepReply()
    clock.release(upTo: 5)
    await settle()

    XCTAssertFalse(vm.replyDismissed, "the paused reply must outlive the countdown it replaced")

    vm.resumeReplyDismiss(hold: 2.5)
    await settle()

    XCTAssertEqual(clock.holds, [5, NotchViewModel.heldReplyMaxHold, 2.5])
    XCTAssertTrue(vm.replyDismissed, "the resumed hold was already released")
  }

  /// The pause is a ceiling, not a cancellation. The pointer can leave without
  /// the notch ever hearing about it — the panel is ordered out, the display
  /// goes away, the app is hidden — and a reply held open by a resume that never
  /// arrives would sit on the user's screen until the next voice turn.
  func testAPausedReplyStillEndsWhenTheResumeNeverArrives() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })
    vm.noteReply("Here is the answer")
    vm.beginReplyDismiss(hold: 5)
    await settle()

    vm.keepReply()
    await settle()

    XCTAssertEqual(clock.holds, [5, NotchViewModel.heldReplyMaxHold])
    clock.release(upTo: 5)
    await settle()
    XCTAssertTrue(vm.isLingeringReply, "the ceiling has to outlast a long read, not cut it short")

    clock.release(upTo: NotchViewModel.heldReplyMaxHold)
    await settle()

    XCTAssertTrue(vm.replyDismissed)
    XCTAssertFalse(vm.isLingeringReply)
  }

  /// The same missing state, in the other direction: a turn that ends while the
  /// pointer is already resting on the notch used to start the short countdown
  /// anyway and pull the reply out from under someone reading it.
  func testAReplyThatFinishesUnderThePointerTakesTheCeilingNotTheShortHold() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })

    vm.keepReply()
    vm.noteReply("Here is the answer")
    vm.beginReplyDismiss(hold: 5)
    await settle()

    XCTAssertEqual(clock.holds, [NotchViewModel.heldReplyMaxHold])

    clock.release(upTo: 5)
    await settle()
    XCTAssertFalse(vm.replyDismissed)

    // And the pointer leaving still hands it back to the short grace.
    vm.resumeReplyDismiss(hold: 2.5)
    await settle()

    XCTAssertEqual(clock.holds, [NotchViewModel.heldReplyMaxHold, 2.5])
    XCTAssertTrue(vm.replyDismissed)
  }

  func testEscDismissesImmediatelyWithoutWaitingOutTheHold() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })
    vm.noteReply("Here is the answer")
    vm.beginReplyDismiss(hold: 5)
    await settle()

    vm.dismissReply()

    XCTAssertTrue(vm.replyDismissed)
    XCTAssertFalse(vm.isLingeringReply)
  }

  /// A new turn starts from nothing: the previous reply, its dismissal flag and
  /// the measured voice height all go, so the panel cannot open at the last
  /// answer's height.
  func testANewTurnResetsEveryPieceOfReplyState() async {
    let clock = LingerClock()
    let vm = makeViewModel(sleep: { [clock] in await clock.hold($0) })
    vm.noteReply("Here is the answer")
    vm.voiceBodyHeight = 260
    vm.beginReplyDismiss(hold: 5)
    await settle()

    vm.resetReply()

    XCTAssertEqual(vm.heldReply, "")
    XCTAssertFalse(vm.replyDismissed)
    XCTAssertNil(vm.voiceBodyHeight)
    XCTAssertFalse(vm.isLingeringReply)

    // The countdown the reset cancelled must not fire against the fresh turn.
    clock.release()
    await settle()
    XCTAssertFalse(vm.replyDismissed)
  }

  /// Lets the linger task observe a release or a cancellation. The clock never
  /// sleeps, so this is bounded cooperative scheduling, not a timed wait.
  private func settle() async {
    for _ in 0..<64 { await Task.yield() }
  }
}
