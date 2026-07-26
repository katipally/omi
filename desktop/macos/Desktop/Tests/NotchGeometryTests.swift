import AppKit
import XCTest

@testable import Omi_Computer

/// The closed notch must look the same on every display. Before this was
/// enforced, a screen with no camera housing fell back to a bare 240pt bar and
/// the mark/gear cluster floated inside it with no relationship to the center.
final class NotchGeometryTests: XCTestCase {
  private let lobes = NotchMetrics.closedSideWidth * 2

  private func closedSize(left: NSRect?, right: NSRect?, topInset: CGFloat = 0) -> CGSize {
    NotchMetrics.closedSize(
      auxiliaryTopLeftArea: left,
      auxiliaryTopRightArea: right,
      topSafeAreaInset: topInset,
      frameMaxY: 1000,
      visibleFrameMaxY: 975
    )
  }

  func testDisplayWithoutCameraHousingStillReservesTheDeadZone() {
    let size = closedSize(left: nil, right: nil)

    let synthesized = NotchMetrics.fallbackHiddenCenterWidth + NotchMetrics.hiddenCenterSafetyPadding
    XCTAssertEqual(size.width, synthesized + lobes)
    // The regression: a hardcoded width unrelated to the chrome it holds.
    XCTAssertNotEqual(size.width, 240)
  }

  func testMeasuredHousingWidensTheDeadZoneByTheSafetyPadding() {
    let left = NSRect(x: 0, y: 0, width: 500, height: 38)
    let right = NSRect(x: 700, y: 0, width: 500, height: 38)

    let size = closedSize(left: left, right: right, topInset: 38)

    XCTAssertEqual(size.width, 200 + NotchMetrics.hiddenCenterSafetyPadding + lobes)
    XCTAssertEqual(size.height, 38, "A physical notch sizes the chrome to its own height")
  }

  func testNarrowMeasuredHousingIsFlooredAtTheFallbackDeadZone() {
    let left = NSRect(x: 0, y: 0, width: 500, height: 38)
    let right = NSRect(x: 560, y: 0, width: 500, height: 38)

    let size = closedSize(left: left, right: right, topInset: 38)

    let floor = NotchMetrics.fallbackHiddenCenterWidth + NotchMetrics.hiddenCenterSafetyPadding
    XCTAssertEqual(size.width, floor + lobes)
  }

  func testCameraWidthFallsBackWhenTheHousingCannotBeMeasured() {
    XCTAssertEqual(
      NotchMetrics.cameraWidth(auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil),
      NotchMetrics.fallbackHiddenCenterWidth
    )
    XCTAssertEqual(
      NotchMetrics.cameraWidth(auxiliaryTopLeftArea: .zero, auxiliaryTopRightArea: .zero),
      NotchMetrics.fallbackHiddenCenterWidth
    )
    XCTAssertEqual(
      NotchMetrics.cameraWidth(
        auxiliaryTopLeftArea: NSRect(x: 0, y: 0, width: 500, height: 38),
        auxiliaryTopRightArea: NSRect(x: 700, y: 0, width: 500, height: 38)
      ),
      200
    )
  }

  /// The dead zone is what the chrome straddles, so it must always leave room
  /// for both lobes plus the margin the mark and gear sit in.
  func testDeadZoneAlwaysExceedsTheCameraItHides() {
    let left = NSRect(x: 0, y: 0, width: 500, height: 38)
    let right = NSRect(x: 700, y: 0, width: 500, height: 38)

    let camera = NotchMetrics.cameraWidth(auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right)
    let deadZone = NotchMetrics.hiddenCenterWidth(
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right)

    XCTAssertEqual(deadZone - camera, NotchMetrics.hiddenCenterSafetyPadding)
  }

  func testClosedHeightPrefersTheSafeAreaThenTheMenuBarStrip() {
    XCTAssertEqual(
      NotchMetrics.closedHeight(topSafeAreaInset: 38, frameMaxY: 1000, visibleFrameMaxY: 975),
      38
    )
    // No safe area: the strip between frame and visible frame, minus the 1pt seam.
    XCTAssertEqual(
      NotchMetrics.closedHeight(topSafeAreaInset: 0, frameMaxY: 1000, visibleFrameMaxY: 940),
      59
    )
    // Floored, so a display reporting a hairline strip still gets usable chrome.
    XCTAssertEqual(
      NotchMetrics.closedHeight(topSafeAreaInset: 0, frameMaxY: 1000, visibleFrameMaxY: 999),
      NotchMetrics.fallbackClosedHeight
    )
  }
}
