import AppKit
import SwiftUI
import XCTest

@testable import OmiTheme
@testable import Omi_Computer

/// The app detail sheet opened with a full-width row holding nothing but a
/// close glyph, and pinned itself to a fixed 600pt whatever it held. Both are
/// layout facts, so they are measured by layout: the header is mounted in a
/// real `NSHostingView` and asked how tall it is.
///
/// `OmiSheetHeader` cannot be built without a title, so an empty band is no
/// longer representable; what still needs proving is that the title is laid out
/// *inside* the band, that the accessories share its row instead of stacking
/// another one under it, and that a short sheet measures its own content.
@MainActor
final class SheetChromeHeaderLayoutTests: XCTestCase {
  private static let sheetWidth: CGFloat = 500
  /// What the detail sheet used to hardcode, so a short sheet can be measured
  /// against the floor it no longer has.
  private static let retiredFixedSheetHeight: CGFloat = 600
  /// The divider and font rounding on top of one band. A second row of chrome
  /// would add the control height again and blow straight through this.
  private static let bandSlack: CGFloat = 16

  private var oneBand: CGFloat { OmiChrome.controlHeight + OmiSpacing.lg * 2 }

  func testHeaderBandIsOneRowAndCarriesItsTitle() {
    let short = measuredHeight(
      OmiSheetHeader(title: "OpenClaw", subtitle: "Mohsin", onClose: {})
    )
    let wrapped = measuredHeight(
      OmiSheetHeader(title: Self.wrappingTitle, subtitle: "Mohsin", onClose: {})
    )

    XCTAssertGreaterThan(short, 0, "The header laid nothing out, so the measurement proves nothing.")
    XCTAssertGreaterThanOrEqual(
      short, oneBand,
      "The header band collapsed below one control row plus its inset."
    )
    XCTAssertLessThanOrEqual(
      short, oneBand + Self.bandSlack,
      "A one-line title cost \(short)pt of chrome, more than the single band \(oneBand)pt buys."
    )
    XCTAssertGreaterThan(
      wrapped, short,
      "A title long enough to wrap did not make the band taller, so the title is not being laid out inside it."
    )
  }

  func testAccessoriesShareTheTitleRowInsteadOfStackingUnderIt() {
    let plain = measuredHeight(OmiSheetHeader(title: "OpenClaw", subtitle: "Mohsin", onClose: {}))
    let dressed = measuredHeight(
      OmiSheetHeader(
        title: "OpenClaw",
        subtitle: "Mohsin",
        onClose: {},
        leading: { Self.iconStub },
        trailing: { Self.actionStub }
      )
    )

    XCTAssertEqual(
      dressed, plain, accuracy: 1,
      "The icon and the actions added a row instead of sitting on the title's: \(plain)pt -> \(dressed)pt."
    )
  }

  func testShortSheetMeasuresItsContentInsteadOfAFixedHeight() {
    let header = OmiSheetHeader(
      title: "OpenClaw",
      subtitle: "Mohsin",
      onClose: {},
      leading: { Self.iconStub },
      trailing: { Self.actionStub }
    )
    let body = Text("A one-line About section, the whole of a brand new app's detail.")
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(OmiSpacing.lg)

    let headerHeight = measuredHeight(header)
    let bodyHeight = measuredHeight(body)
    let sheetHeight = measuredHeight(
      VStack(spacing: 0) {
        header
        body
      }
    )

    XCTAssertEqual(
      sheetHeight, headerHeight + bodyHeight, accuracy: 1,
      "A sheet stacked from this chrome is not the sum of its parts, so something is imposing a height."
    )
    XCTAssertLessThan(
      sheetHeight, Self.retiredFixedSheetHeight,
      "Short content still measures \(sheetHeight)pt, at or past the fixed height the sheet used to pin itself to."
    )
  }

  // MARK: - Harness

  private static let wrappingTitle =
    "OpenClaw Workspace Companion For Very Long Marketplace Listing Names That Have To Wrap"

  private static var iconStub: some View {
    RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
      .fill(OmiColors.backgroundTertiary)
      .frame(width: OmiChrome.controlHeight, height: OmiChrome.controlHeight)
  }

  private static var actionStub: some View {
    RoundedRectangle(cornerRadius: OmiChrome.controlRadius)
      .fill(OmiColors.backgroundSecondary)
      .frame(width: 100, height: 36)
  }

  private func measuredHeight(_ view: some View) -> CGFloat {
    let host = NSHostingView(rootView: view.frame(width: Self.sheetWidth))
    host.frame = NSRect(x: 0, y: 0, width: Self.sheetWidth, height: Self.retiredFixedSheetHeight)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.height
  }
}
