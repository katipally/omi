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

  /// Regression: pinning the unmeasured frame to `maxHeight` leaves a modal
  /// whose measurement never lands stuck at full height, with dead space above
  /// and below its content. Unmeasured must mean "size naturally", not "size
  /// tallest".
  func testUnmeasuredContentIsUnconstrainedRatherThanPinnedToTheCap() {
    XCTAssertNil(FittedModalGeometry.height(contentHeight: 0, maxHeight: 650))
  }
}
