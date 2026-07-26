import XCTest

@testable import OmiTheme
@testable import Omi_Computer

/// The jump-to-latest chip is pinned to the same `ZStack` bottom that Home's ask
/// bar floats over, so a bare gap put the one affordance for reaching the live
/// edge *inside* the composer. The inset is the contract that keeps them apart.
final class ChatJumpButtonPlacementTests: XCTestCase {
  func testTheChipClearsAFloatingComposerWhateverHeightItGrowsTo() {
    for composerHeight in [CGFloat(48), 96, 240] {
      let inset = ChatJumpButtonPlacement.bottomInset(composerCoverHeight: composerHeight)
      XCTAssertGreaterThan(
        inset, composerHeight,
        "a \(composerHeight)pt composer would still cover the chip at \(inset)pt")
    }
  }

  /// ChatPage, the agent sheet and the task panel dock their composers below the
  /// transcript and report no cover, so they must keep the bare gap they had.
  func testASurfaceWithNoFloatingComposerKeepsItsBareGap() {
    XCTAssertEqual(
      ChatJumpButtonPlacement.bottomInset(composerCoverHeight: 0), ChatJumpButtonPlacement.gap)
  }

  /// The cover height is measured from live geometry, which reports a negative
  /// height during teardown. Padding by it would drag the chip off screen.
  func testAMeasurementGlitchNeverPullsTheChipBelowTheStage() {
    XCTAssertEqual(
      ChatJumpButtonPlacement.bottomInset(composerCoverHeight: -120), ChatJumpButtonPlacement.gap)
  }
}
