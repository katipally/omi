import XCTest

@testable import Omi_Computer

/// Moment cards on the notch surface.
///
/// The ported notch package predated upstream's moments system, so its
/// notification card only knew `reach_error` and `task`: a saved-task receipt
/// or a conversation-end card fell through to the generic proactive card,
/// losing Review / Undo / Later.
final class NotchMomentCardTests: XCTestCase {
  func testMomentCardsFitTheirOwnHeightRatherThanTheFullNotificationSlab() {
    let receipt = NotchMetrics.notificationHeight(forAssistantId: NotchMoment.receiptAssistantId)
    let end = NotchMetrics.notificationHeight(forAssistantId: NotchMoment.endAssistantId)
    let proactive = NotchMetrics.notificationHeight(forAssistantId: "some_assistant")

    // A one-line receipt in the full proactive slab leaves an empty panel of
    // black under it; the end card sits between the two.
    XCTAssertLessThan(receipt, end)
    XCTAssertLessThan(end, proactive)
    XCTAssertEqual(proactive, NotchMetrics.notificationSize.height)
  }

  func testUnknownAndMissingAssistantIdsKeepTheProactiveHeight() {
    XCTAssertEqual(
      NotchMetrics.notificationHeight(forAssistantId: nil), NotchMetrics.notificationSize.height)
    XCTAssertEqual(
      NotchMetrics.notificationHeight(forAssistantId: "reach_error"),
      NotchMetrics.notificationSize.height)
  }

  @MainActor
  func testPanelHeightTracksTheCardSoTheNotchDoesNotOverGrow() {
    let vm = NotchViewModel(
      displayID: 1,
      screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      hasPhysicalNotch: true,
      closedNotchSize: CGSize(width: 266, height: 38),
      now: { Date(timeIntervalSinceReferenceDate: 0) },
      sleep: { _ in },
      defaults: UserDefaults(suiteName: "NotchMomentCardTests")!
    )
    let receiptHeight = NotchMetrics.notificationHeight(
      forAssistantId: NotchMoment.receiptAssistantId)

    let sized: CGSize = vm.size(
      for: NotchPresentation.notification(UUID()), notificationCardHeight: receiptHeight)
    let full: CGSize = vm.size(for: NotchPresentation.notification(UUID()))

    XCTAssertLessThan(sized.height, full.height)
    XCTAssertEqual(sized.width, full.width)
  }
}
