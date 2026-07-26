import AppKit
import SwiftUI
import XCTest

@testable import OmiTheme
@testable import Omi_Computer

/// The Apps header shipped with its install-scope segments compressed to an
/// empty blob: the search field was the row's only flexible control and had a
/// layout priority on top of that, so it took the whole width and left the
/// labelled controls at their truncation size. These assert the real row's
/// layout pass rather than the modifiers that produce it.
@MainActor
final class AppsHeaderRowLayoutTests: XCTestCase {
  private static let scopeSegments = ["All", "Installed"]

  func testTheInstallScopeSegmentsKeepTheirLabelsOnAWideWindow() {
    let placed = layOutHeader(width: 1000)

    XCTAssertGreaterThanOrEqual(
      placed.width, legibleScopeWidth - 0.5,
      "the scope segments were squeezed to \(placed.width)pt of a needed \(legibleScopeWidth)pt")
  }

  /// The window the screenshot came from. A cap that only holds on a huge
  /// display is not a fix.
  func testTheSegmentsSurviveAnOrdinaryWindowWidth() {
    let placed = layOutHeader(width: 720)

    XCTAssertGreaterThanOrEqual(
      placed.width, legibleScopeWidth - 0.5,
      "the scope segments were squeezed to \(placed.width)pt of a needed \(legibleScopeWidth)pt")
  }

  /// Narrow enough that the row must stack. The segments still may not shrink.
  func testTheStackedArmAlsoLeavesTheSegmentsLegible() {
    let placed = layOutHeader(width: 380)

    XCTAssertGreaterThanOrEqual(
      placed.width, legibleScopeWidth - 0.5,
      "the stacked arm squeezed the scope segments to \(placed.width)pt")
  }

  /// The search field is still the control that absorbs slack — the cap must not
  /// have turned the row into four controls huddled on the leading edge.
  func testTheSearchFieldStillTakesTheSlackUpToItsCap() {
    let recorder = LayoutRecorder()
    layOut(width: 1000, recorder: recorder)

    guard let search = recorder.frame(of: .search) else {
      return XCTFail("the search field never laid out")
    }
    XCTAssertEqual(search.width, AppsHeaderMetrics.searchFieldMaxWidth, accuracy: 0.5)
  }

  // MARK: - Harness

  /// What the two segments need when nothing is competing for the width.
  private var legibleScopeWidth: CGFloat {
    let host = NSHostingView(
      rootView: OmiSegmentedControl(segments: Self.scopeSegments, selection: .constant(0))
        .fixedSize()
    )
    return host.fittingSize.width
  }

  private func layOutHeader(width: CGFloat) -> CGRect {
    let recorder = LayoutRecorder()
    layOut(width: width, recorder: recorder)
    guard let placed = recorder.frame(of: .filters) else {
      XCTFail("the filter controls never laid out")
      return .zero
    }
    return placed
  }

  private func layOut(width: CGFloat, recorder: LayoutRecorder) {
    let host = NSHostingView(
      rootView: AppsHeaderRow(
        search: {
          LayoutProbe(recorder: recorder, slot: .search) {
            // Stands in for OmiSearchField: flexible in both directions, which
            // is exactly the greed the cap exists to bound.
            Color.clear.frame(maxWidth: .infinity).frame(height: OmiChrome.controlHeight)
          }
        },
        filters: {
          LayoutProbe(recorder: recorder, slot: .filters) {
            OmiSegmentedControl(segments: Self.scopeSegments, selection: .constant(0))
          }
        },
        create: { Color.clear.frame(width: 110, height: OmiChrome.controlHeight) },
        dismiss: { EmptyView() }
      )
      .frame(width: width)
    )
    host.frame = NSRect(x: 0, y: 0, width: width, height: 200)
    host.layoutSubtreeIfNeeded()
  }
}

private enum LayoutSlot {
  case search
  case filters
}

/// `Layout` requirements are not main-actor isolated, so the record is
/// lock-guarded rather than assumed to run on one thread.
private final class LayoutRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var frames: [LayoutSlot: CGRect] = [:]

  func record(_ slot: LayoutSlot, _ frame: CGRect) {
    lock.lock()
    frames[slot] = frame
    lock.unlock()
  }

  func frame(of slot: LayoutSlot) -> CGRect? {
    lock.lock()
    defer { lock.unlock() }
    return frames[slot]
  }
}

/// Records the region SwiftUI hands its content. A plain pass-through otherwise,
/// so what it reports is the geometry the real control would have been given.
private struct LayoutProbe: Layout {
  let recorder: LayoutRecorder
  let slot: LayoutSlot

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    var size = CGSize.zero
    for subview in subviews {
      let child = subview.sizeThatFits(proposal)
      size.width = max(size.width, child.width)
      size.height = max(size.height, child.height)
    }
    return size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    recorder.record(slot, bounds)
    for subview in subviews {
      subview.place(
        at: CGPoint(x: bounds.minX, y: bounds.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
      )
    }
  }
}
