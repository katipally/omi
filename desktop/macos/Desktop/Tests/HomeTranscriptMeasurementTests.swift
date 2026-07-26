import AppKit
import SwiftUI
import XCTest

@testable import OmiTheme
@testable import Omi_Computer

/// A field hang put the main thread on-CPU inside SwiftUI layout for sixteen
/// seconds, under `DashboardPage.homePanelStage` -> `ChatMessagesView`'s
/// `LazyVStack` -> `ChatBubble`'s per-row `ForEach` over its content-block
/// groups. The reading offered was that a transcript row being *itself* a
/// dynamic list makes the stack's work grow faster than the transcript does.
///
/// That is a claim about shape, so it is measured by shape. A stub transcript
/// with the same nesting is mounted in a real `NSHostingView` and asked how much
/// layout work one row costs at two very different lengths. Two tallies are
/// kept, because the reported stack implicates both halves of a layout pass:
/// `sizeThatFits` calls (what the stack measures) and row-body materialisations
/// (what the node walk builds before anything is measured).
///
/// Counts, never wall-clock. The question is whether the per-row cost is
/// scale-invariant; a duration would only measure the machine it ran on.
@MainActor final class HomeTranscriptMeasurementTests: XCTestCase {

  private static let shortTranscript = 20
  private static let longTranscript = 200
  /// A real assistant turn groups into a handful of blocks — prose, a tool
  /// group, prose again. Four keeps the nesting honest without making the stub
  /// a stress test of something the app never renders.
  private static let blocksPerRow = 4

  /// Home's own geometry: the readable column is capped at 680 on the stack
  /// while the scroll view spans the shell.
  private static let columnWidth: CGFloat = 680
  private static let viewport = CGSize(width: 900, height: 620)

  /// A settled transcript taking four more tokens. Applied identically at both
  /// lengths, so the comparison stays a comparison.
  private static let streamingTicks = [
    " the", " the reply", " the reply keeps", " the reply keeps arriving",
  ]

  /// A per-row cost that grows with N is what "quadratic" means here, and going
  /// from 20 rows to 200 would multiply it by ten. The slack therefore only has
  /// to absorb constant jitter: a quarter over the short transcript's own
  /// figure — which carries the stack's fixed cost spread across a tenth as many
  /// rows, and so already reads high — plus one whole extra call per row.
  private static let perRowGrowthAllowance = 1.25
  private static let perRowConstantAllowance = 1.0

  /// How much more the nested shape may grow than the flat one before nesting,
  /// rather than transcript length, is the thing on trial.
  private static let nestingGrowthAllowance = 0.5

  func testPerRowTranscriptLayoutCostDoesNotGrowWithTranscriptLength() {
    let short = measureTranscript(rowCount: Self.shortTranscript, nested: true)
    let long = measureTranscript(rowCount: Self.longTranscript, nested: true)

    XCTAssertGreaterThan(
      short.measurements, 0,
      "No row was ever asked for a size — the harness measured nothing, so it proves nothing."
    )
    XCTAssertGreaterThan(
      short.materializations, 0,
      "No row body was ever built — the harness measured nothing, so it proves nothing."
    )

    assertPerRowCostIsFlat(
      shortCount: short.measurements,
      longCount: long.measurements,
      label: "row size measurements"
    )
    assertPerRowCostIsFlat(
      shortCount: short.materializations,
      longCount: long.materializations,
      label: "row body materialisations"
    )
  }

  /// The controlled half. A stack that costs more per row at 200 rows for
  /// reasons of its own would fail the test above without telling us why, so the
  /// same transcript is measured with the nesting collapsed to one static child.
  /// Only growth the nested shape shows *and the flat one does not* is growth
  /// the per-row `ForEach` is responsible for.
  func testNestedRowShapeIsNotWhatMakesPerRowCostGrow() {
    let nestedShort = measureTranscript(rowCount: Self.shortTranscript, nested: true)
    let nestedLong = measureTranscript(rowCount: Self.longTranscript, nested: true)
    let flatShort = measureTranscript(rowCount: Self.shortTranscript, nested: false)
    let flatLong = measureTranscript(rowCount: Self.longTranscript, nested: false)

    XCTAssertGreaterThan(nestedShort.materializations, 0, "Nested harness laid nothing out.")
    XCTAssertGreaterThan(flatShort.materializations, 0, "Flat harness laid nothing out.")

    let nestedGrowth = perRowGrowth(
      shortCount: nestedShort.materializations, longCount: nestedLong.materializations)
    let flatGrowth = perRowGrowth(
      shortCount: flatShort.materializations, longCount: flatLong.materializations)

    XCTAssertLessThanOrEqual(
      nestedGrowth, flatGrowth + Self.nestingGrowthAllowance,
      """
      Per-row cost grew faster for the nested row than for the flat one, \
      which is the nesting hypothesis: nested \(nestedShort.materializations) -> \
      \(nestedLong.materializations) (growth \(nestedGrowth)), flat \
      \(flatShort.materializations) -> \(flatLong.materializations) (growth \(flatGrowth)).
      """
    )
  }

  // MARK: - Measurement

  private struct TranscriptLayoutMeasurement {
    let measurements: Int
    let materializations: Int
  }

  private func measureTranscript(rowCount: Int, nested: Bool)
    -> TranscriptLayoutMeasurement
  {
    let tally = TranscriptLayoutTally()
    let rows = TranscriptStub.rows(count: rowCount, blocksPerRow: Self.blocksPerRow)

    let host = NSHostingView(
      rootView: TranscriptMeasurementHarness(
        tally: tally,
        rows: rows,
        nested: nested,
        columnWidth: Self.columnWidth,
        streamingTail: ""
      )
    )
    host.frame = NSRect(origin: .zero, size: Self.viewport)
    host.layoutSubtreeIfNeeded()

    for tail in Self.streamingTicks {
      host.rootView = TranscriptMeasurementHarness(
        tally: tally,
        rows: rows,
        nested: nested,
        columnWidth: Self.columnWidth,
        streamingTail: tail
      )
      host.layoutSubtreeIfNeeded()
    }

    return TranscriptLayoutMeasurement(
      measurements: tally.measurementCount,
      materializations: tally.materializationCount
    )
  }

  private func perRowGrowth(shortCount: Int, longCount: Int) -> Double {
    let perRowShort = Double(shortCount) / Double(Self.shortTranscript)
    guard perRowShort > 0 else { return .infinity }
    return (Double(longCount) / Double(Self.longTranscript)) / perRowShort
  }

  private func assertPerRowCostIsFlat(
    shortCount: Int,
    longCount: Int,
    label: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let perRowShort = Double(shortCount) / Double(Self.shortTranscript)
    let perRowLong = Double(longCount) / Double(Self.longTranscript)
    let ceiling = perRowShort * Self.perRowGrowthAllowance + Self.perRowConstantAllowance

    XCTAssertLessThanOrEqual(
      perRowLong, ceiling,
      """
      Per-row \(label) grew with transcript length: \
      \(Self.shortTranscript) rows -> \(shortCount) (\(perRowShort)/row), \
      \(Self.longTranscript) rows -> \(longCount) (\(perRowLong)/row), \
      ceiling \(ceiling)/row.
      """,
      file: file, line: line
    )
  }
}

// MARK: - Tally

/// `Layout` requirements are not main-actor isolated, so the tally is
/// lock-guarded rather than assumed to run on one thread.
private final class TranscriptLayoutTally: @unchecked Sendable {
  private let lock = NSLock()
  private var measurements = 0
  private var materializations = 0

  func recordMeasurement() {
    lock.lock()
    measurements += 1
    lock.unlock()
  }

  func recordMaterialization() {
    lock.lock()
    materializations += 1
    lock.unlock()
  }

  var measurementCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return measurements
  }

  var materializationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return materializations
  }
}

// MARK: - Measuring layout

/// Counts every size SwiftUI asks the wrapped row for. It is a plain vertical
/// pass-through otherwise, so what it records is the measurement the row would
/// have been asked for anyway.
private struct MeasuringLayout: Layout {
  let tally: TranscriptLayoutTally

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    tally.recordMeasurement()
    var size = CGSize.zero
    for subview in subviews {
      let child = subview.sizeThatFits(proposal)
      size.width = max(size.width, child.width)
      size.height += child.height
    }
    return size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for subview in subviews {
      let child = subview.sizeThatFits(proposal)
      subview.place(
        at: CGPoint(x: bounds.minX, y: y),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: child.height)
      )
      y += child.height
    }
  }
}

// MARK: - Stub transcript

private struct TranscriptStubBlock: Identifiable {
  let id: String
  let text: String
}

private struct TranscriptStubRow: Identifiable {
  let id: String
  let sender: ChatSender
  let leadingGap: CGFloat
  let blocks: [TranscriptStubBlock]

  var flattened: String {
    blocks.map(\.text).joined(separator: "\n")
  }
}

private enum TranscriptStub {
  static func rows(count: Int, blocksPerRow: Int) -> [TranscriptStubRow] {
    var rows: [TranscriptStubRow] = []
    rows.reserveCapacity(count)
    var previous: ChatSender?

    for index in 0..<count {
      let sender: ChatSender = index.isMultiple(of: 2) ? .user : .ai
      let blocks = (0..<blocksPerRow).map { block in
        TranscriptStubBlock(
          id: "\(index)-\(block)",
          text: "Row \(index), block \(block): a sentence of transcript prose long enough to wrap."
        )
      }
      rows.append(
        TranscriptStubRow(
          id: "row-\(index)",
          sender: sender,
          leadingGap: ChatTurnSpacing.leadingGap(previous: previous, current: sender),
          blocks: blocks
        )
      )
      previous = sender
    }

    return rows
  }
}

// MARK: - Harness views

/// Mirrors `ChatMessagesView.scrollContent`: one `LazyVStack` of rows inside a
/// real `ScrollView`, the readable column capped on the stack rather than on the
/// scroll view, and the turn gap carried per row by the production helper.
private struct TranscriptMeasurementHarness: View {
  let tally: TranscriptLayoutTally
  let rows: [TranscriptStubRow]
  let nested: Bool
  let columnWidth: CGFloat
  let streamingTail: String

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(rows) { row in
          rowView(row)
            .padding(.top, row.leadingGap)
            .id(row.id)
        }
      }
      .padding(.vertical, OmiSpacing.sm)
      .frame(maxWidth: columnWidth)
      .frame(maxWidth: .infinity)
    }
  }

  @ViewBuilder
  private func rowView(_ row: TranscriptStubRow) -> some View {
    let tail = row.id == rows.last?.id ? streamingTail : ""
    if nested {
      NestedStubRow(tally: tally, row: row, tail: tail)
    } else {
      FlatStubRow(tally: tally, row: row, tail: tail)
    }
  }
}

/// The shape on trial: the row is itself a dynamic list, as a real assistant
/// turn is a `ForEach` over its content-block groups.
private struct NestedStubRow: View {
  let tally: TranscriptLayoutTally
  let row: TranscriptStubRow
  let tail: String

  var body: some View {
    tally.recordMaterialization()
    return MeasuringLayout(tally: tally) {
      VStack(alignment: row.sender == .user ? .trailing : .leading, spacing: OmiSpacing.xxs) {
        ForEach(row.blocks) { block in
          Text(block.text + (block.id == row.blocks.last?.id ? tail : ""))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        StubMetadataRow()
      }
      .frame(maxWidth: .infinity, alignment: row.sender == .user ? .trailing : .leading)
      .contentShape(Rectangle())
    }
  }
}

/// The control: same content, same wrapper, one static child instead of a
/// nested list.
private struct FlatStubRow: View {
  let tally: TranscriptLayoutTally
  let row: TranscriptStubRow
  let tail: String

  var body: some View {
    tally.recordMaterialization()
    return MeasuringLayout(tally: tally) {
      VStack(alignment: row.sender == .user ? .trailing : .leading, spacing: OmiSpacing.xxs) {
        Text(row.flattened + tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        StubMetadataRow()
      }
      .frame(maxWidth: .infinity, alignment: row.sender == .user ? .trailing : .leading)
      .contentShape(Rectangle())
    }
  }
}

/// `ChatBubble`'s metadata strip: a fixed-shape row under every message.
private struct StubMetadataRow: View {
  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      Text(verbatim: "Copy")
        .scaledFont(size: OmiType.micro, weight: .medium)
      Text(verbatim: "12:04")
        .scaledFont(size: OmiType.micro, weight: .medium)
    }
  }
}
