import XCTest

@testable import Omi_Computer

/// The Listening chip is the last thing in the shell top bar, so the window
/// edge sits immediately to its right and its hover reveal is wider than it is.
/// These pin the placement rule that keeps the panel inside the window.
final class ListeningHoverRevealGeometryTests: XCTestCase {
  /// Widths the Listening chip takes across its capture modes — the mode title
  /// and the badge are what move it.
  private let chipWidths: [CGFloat] = [130, 158, 186, 219]

  /// The picker's floor at 1.0x; every row carries `minWidth: 224`.
  private let basePanelWidth: CGFloat = 224

  /// Reduce/increase text size scales the chip and the panel together.
  private let fontScales: [CGFloat] = [1, 2]

  private let containerWidth: CGFloat = 1000

  func testTrailingAnchoredPanelStaysInsideTheContainer() {
    forEachRealisticCase { chipWidth, panelWidth, label in
      let bounds = HoverRevealAnchor.chipTrailing.panelBounds(
        chipWidth: chipWidth, panelWidth: panelWidth, containerWidth: containerWidth)

      XCTAssertLessThanOrEqual(bounds.upperBound, containerWidth, label)
      XCTAssertGreaterThanOrEqual(bounds.lowerBound, 0, label)
      XCTAssertEqual(bounds.upperBound - bounds.lowerBound, panelWidth, accuracy: 0.001, label)
    }
  }

  /// Staying inside the window is not enough on its own — a panel shoved to the
  /// window edge would drift off its chip. The trailing edges have to coincide.
  func testTrailingAnchoredPanelLandsOnTheChipTrailingEdge() {
    forEachRealisticCase { chipWidth, panelWidth, label in
      let bounds = HoverRevealAnchor.chipTrailing.panelBounds(
        chipWidth: chipWidth, panelWidth: panelWidth, containerWidth: containerWidth)

      XCTAssertEqual(bounds.upperBound, containerWidth, accuracy: 0.001, label)
      XCTAssertEqual(bounds.lowerBound, containerWidth - panelWidth, accuracy: 0.001, label)
    }
  }

  /// The centre anchor is what a chip with room on both sides uses. On a chip
  /// flush with the container's trailing edge it puts half the width difference
  /// outside the window, at every realistic chip width and both font scales.
  func testCenterAnchorOverhangsForEveryRealisticChipWidth() {
    forEachRealisticCase { chipWidth, panelWidth, label in
      let bounds = HoverRevealAnchor.chipCenter.panelBounds(
        chipWidth: chipWidth, panelWidth: panelWidth, containerWidth: containerWidth)

      XCTAssertGreaterThan(bounds.upperBound, containerWidth, label)
      XCTAssertEqual(
        bounds.upperBound - containerWidth, (panelWidth - chipWidth) / 2, accuracy: 0.001, label)
    }
  }

  /// A panel narrower than its chip has nothing to spill, so the anchor choice
  /// is only ever about the wide case.
  func testNarrowPanelFitsUnderEitherAnchor() {
    for anchor in [HoverRevealAnchor.chipCenter, .chipTrailing] {
      let bounds = anchor.panelBounds(
        chipWidth: 219, panelWidth: 80, containerWidth: containerWidth)
      XCTAssertLessThanOrEqual(bounds.upperBound, containerWidth)
    }
  }

  private func forEachRealisticCase(
    _ body: (_ chipWidth: CGFloat, _ panelWidth: CGFloat, _ label: String) -> Void
  ) {
    for scale in fontScales {
      for chipWidth in chipWidths {
        body(chipWidth * scale, basePanelWidth * scale, "chip \(chipWidth) at \(scale)x")
      }
    }
  }
}
