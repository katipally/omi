import XCTest

@testable import OmiTheme

final class FittedModalGeometryTests: XCTestCase {
  func testShortContentSizesToItself() {
    XCTAssertEqual(FittedModalGeometry.height(contentHeight: 220, maxHeight: 650), 220)
    XCTAssertFalse(FittedModalGeometry.isCapped(contentHeight: 220, maxHeight: 650))
  }

  func testTallContentCapsAtMaxHeight() {
    XCTAssertEqual(FittedModalGeometry.height(contentHeight: 1200, maxHeight: 650), 650)
    XCTAssertTrue(FittedModalGeometry.isCapped(contentHeight: 1200, maxHeight: 650))
  }

  func testContentExactlyAtTheCapFillsItWithoutBeingCapped() {
    XCTAssertEqual(FittedModalGeometry.height(contentHeight: 650, maxHeight: 650), 650)
    XCTAssertFalse(FittedModalGeometry.isCapped(contentHeight: 650, maxHeight: 650))
  }

  /// Regression: unmeasured content must collapse the frame, not leave it
  /// unconstrained. These sheets contain a greedy `ScrollView`; given an
  /// unconstrained pass it reports the whole proposal back as its content
  /// height and the modal pins to the cap with its content stranded in dead
  /// space. Zero is what makes the first real measurement the content's own.
  func testUnmeasuredContentCollapsesRatherThanTakingTheProposal() {
    XCTAssertEqual(FittedModalGeometry.height(contentHeight: 0, maxHeight: 650), 0)
    XCTAssertFalse(FittedModalGeometry.isCapped(contentHeight: 0, maxHeight: 650))
  }

  func testNegativeMeasurementCannotProduceANegativeHeight() {
    XCTAssertEqual(FittedModalGeometry.height(contentHeight: -40, maxHeight: 650), 0)
  }
}
