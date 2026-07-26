import XCTest

@testable import Omi_Computer

/// The ask bar's trailing slot swaps between four different views. The pill is a
/// bottom-aligned row, so any one of them being taller than the others resizes
/// the whole bar as the user focuses the field or starts a send.
final class HomeAskBarLayoutTests: XCTestCase {
  func testActionModePrecedence() {
    // A send in flight outranks everything: the user needs Stop reachable even
    // with a draft still in the field and focus still held.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: true, canSend: true, isFocused: true),
      .stop
    )
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: true, canSend: false, isFocused: false),
      .stop
    )

    // Text present, nothing in flight: send, focused or not.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: true, isFocused: true),
      .send
    )
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: true, isFocused: false),
      .send
    )

    // Focused and empty: the slot is deliberately empty. Connect would be a
    // second affordance competing with the field the user just clicked into.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: false, isFocused: true),
      .none
    )

    // At rest: Connect is the resting affordance.
    XCTAssertEqual(
      HomeAskBar.actionMode(isSending: false, canSend: false, isFocused: false),
      .connect
    )
  }

  func testEveryActionModeReservesTheSameHeight() throws {
    // omi-test-quality: source-inspection -- static layout tripwire. SwiftUI
    // frames are not measurable without a render host, so this asserts the one
    // structural property that keeps the pill from resizing: the slot's height
    // is applied once, outside the switch, and no arm sets its own.
    let source = try sourceFile("Sources/MainWindow/Pages/HomeAskBar.swift")
    let slot = try XCTUnwrap(
      source.components(separatedBy: "private var actionButton: some View {").last
    )
    let body = try XCTUnwrap(slot.components(separatedBy: "static func actionMode").first)

    XCTAssertTrue(
      body.contains(".frame(height: HomeAskBarMetrics.accessoryHeight)"),
      "the slot must apply one height to every arm"
    )
    // `EmptyView` contributes no height, so the empty arm would drop the row's
    // tallest child and collapse the pill by the difference.
    XCTAssertFalse(
      body.contains("EmptyView()"),
      "the empty arm must reserve height, not vanish"
    )
  }

  func testConnectCapsuleMatchesTheSendCircle() throws {
    // The original defect: a 34pt capsule beside a 30pt circle made the bar 48pt
    // with Connect showing and 44pt without, so clicking into the field moved it.
    let source = try sourceFile("Sources/MainWindow/Pages/HomeAskBar.swift")
    XCTAssertFalse(
      source.contains(".frame(height: 34)"),
      "the Connect capsule must take its height from HomeAskBarMetrics"
    )
    XCTAssertFalse(
      source.contains(".frame(width: 30, height: 30)"),
      "the send and stop circles must take their size from HomeAskBarMetrics"
    )
  }

  // MARK: - Helpers

  private func sourceFile(_ relativePath: String) throws -> String {
    let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourceURL = testsURL.deletingLastPathComponent().appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
