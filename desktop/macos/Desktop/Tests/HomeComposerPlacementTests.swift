import AppKit
import SwiftUI
import XCTest

@testable import OmiTheme
@testable import Omi_Computer

/// Home's composer used to be mounted separately inside each arm of an
/// `if homeMode == .hub` — two structural identities, so hub↔chat destroyed one
/// composer and built another. It could not travel between the two positions,
/// and first responder, hover and drop state all reset on the way. The merged
/// stage keeps one instance and moves it by changing what sits around it, which
/// turns the placement into two decisions worth asserting on their own.
final class HomeComposerPlacementTests: XCTestCase {
  func testTheHubCentresTheComposerAndEveryPanelDocksIt() {
    XCTAssertEqual(HomeComposerPlacement.slot(for: .hub), .centered)
    XCTAssertEqual(HomeComposerPlacement.slot(for: .chat), .docked)
    // The connect tray floats over the same dock; it pads itself clear instead.
    XCTAssertEqual(HomeComposerPlacement.slot(for: .connect), .docked)
  }

  /// The regression most likely to ship unnoticed. Home opens on the hub, then
  /// `onAppear` switches straight to chat for the onboarding opener and for
  /// "Continue in Omi" — a mode change on the first layout pass. Animating that
  /// one slides the composer down from the centre of the window on every launch
  /// that restores a transcript.
  func testLaunchingStraightIntoChatPlacesTheComposerInsteadOfTravellingIt() {
    XCTAssertFalse(
      HomeComposerPlacement.shouldAnimate(from: .hub, to: .chat, isInitialAppearance: true))
    XCTAssertFalse(
      HomeComposerPlacement.shouldAnimate(from: .hub, to: .connect, isInitialAppearance: true))
  }

  func testTheFirstSendTravelsTheComposerAndEscapeTravelsItBack() {
    XCTAssertTrue(
      HomeComposerPlacement.shouldAnimate(from: .hub, to: .chat, isInitialAppearance: false))
    XCTAssertTrue(
      HomeComposerPlacement.shouldAnimate(from: .chat, to: .hub, isInitialAppearance: false))
  }

  func testAModeThatDidNotChangeNeverTravels() {
    XCTAssertFalse(
      HomeComposerPlacement.shouldAnimate(from: .chat, to: .chat, isInitialAppearance: false))
  }
}

/// The trailing slot after a send. The composer now keeps first responder across
/// the travel, and a focused empty field is exactly the state that renders no
/// trailing control — so without an exemption the Connect chip would be gone for
/// good from the first message onwards.
final class HomeAskBarPostSendActionTests: XCTestCase {
  func testConnectSurvivesTheEmptyFieldLeftBehindByASend() {
    XCTAssertEqual(
      HomeAskBar.actionMode(
        isSending: false, canSend: false, isFocused: true, keepsConnectWhileEmpty: true),
      .connect
    )
  }

  func testClickingIntoAnEmptyFieldStillClearsTheSlot() {
    XCTAssertEqual(
      HomeAskBar.actionMode(
        isSending: false, canSend: false, isFocused: true, keepsConnectWhileEmpty: false),
      .none
    )
  }

  func testTheExemptionNeverOutranksSendOrStop() {
    XCTAssertEqual(
      HomeAskBar.actionMode(
        isSending: false, canSend: true, isFocused: true, keepsConnectWhileEmpty: true),
      .send
    )
    XCTAssertEqual(
      HomeAskBar.actionMode(
        isSending: true, canSend: false, isFocused: true, keepsConnectWhileEmpty: true),
      .stop
    )
  }
}

/// The order the cluster reads in, taken from a real layout pass over the
/// production `HomeStageLayout` rather than from the source that builds it.
@MainActor
final class HomeStageLayoutPlacementTests: XCTestCase {
  private static let stage = CGSize(width: 700, height: 800)
  private static let headlineHeight: CGFloat = 120
  private static let composerHeight: CGFloat = 48
  private static let suggestionsHeight: CGFloat = 96

  func testTheHubClusterReadsGreetingThenComposerThenSuggestions() throws {
    let placed = layOutStage(slot: .centered)

    let headline = try XCTUnwrap(placed.frame(of: .headline), "the hub greeting never laid out")
    let composer = try XCTUnwrap(placed.frame(of: .composer), "the composer never laid out")
    let suggestions = try XCTUnwrap(
      placed.frame(of: .suggestions), "the hub suggestion rows never laid out")

    XCTAssertLessThanOrEqual(
      headline.maxY, composer.minY,
      "the composer belongs under the greeting and its welcome line")
    XCTAssertLessThanOrEqual(
      composer.maxY, suggestions.minY,
      "the composer belongs above the suggestion rows")
  }

  func testTheHubClusterSitsMidStageRatherThanAtItsFoot() {
    let placed = layOutStage(slot: .centered)
    guard let composer = placed.frame(of: .composer) else {
      return XCTFail("the composer never laid out")
    }

    XCTAssertGreaterThan(composer.midY, Self.stage.height * 0.25)
    XCTAssertLessThan(composer.midY, Self.stage.height * 0.75)
  }

  /// Docked, the hub's siblings are the only things that leave. That is the
  /// whole mechanism: the composer holds its slot while its neighbours come and
  /// go, so it never loses its identity to a conditional of its own.
  func testDockingDropsTheHubSiblingsAndKeepsTheComposer() {
    let placed = layOutStage(slot: .docked)

    XCTAssertNotNil(placed.frame(of: .composer), "the composer must survive the travel")
    XCTAssertNil(placed.frame(of: .headline))
    XCTAssertNil(placed.frame(of: .suggestions))
  }

  // MARK: - Harness

  private func layOutStage(slot: HomeComposerSlot) -> PlacementRecorder {
    let recorder = PlacementRecorder()
    let host = NSHostingView(
      rootView: HomeStageLayout(
        slot: slot,
        headlineGap: OmiSpacing.xxl,
        suggestionsGap: OmiSpacing.xxl,
        modeContent: { Color.clear },
        headline: {
          PlacementProbe(recorder: recorder, slot: .headline) {
            Color.clear.frame(height: Self.headlineHeight)
          }
        },
        goals: { EmptyView() },
        composer: {
          PlacementProbe(recorder: recorder, slot: .composer) {
            Color.clear.frame(height: Self.composerHeight)
          }
        },
        suggestions: {
          PlacementProbe(recorder: recorder, slot: .suggestions) {
            Color.clear.frame(height: Self.suggestionsHeight)
          }
        }
      )
    )
    host.frame = NSRect(origin: .zero, size: Self.stage)
    host.layoutSubtreeIfNeeded()
    return recorder
  }
}

private enum PlacementSlot {
  case headline
  case composer
  case suggestions
}

/// `Layout` requirements are not main-actor isolated, so the record is
/// lock-guarded rather than assumed to run on one thread.
private final class PlacementRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var frames: [PlacementSlot: CGRect] = [:]

  func record(_ slot: PlacementSlot, _ frame: CGRect) {
    lock.lock()
    frames[slot] = frame
    lock.unlock()
  }

  func frame(of slot: PlacementSlot) -> CGRect? {
    lock.lock()
    defer { lock.unlock() }
    return frames[slot]
  }
}

/// Records the region SwiftUI hands its content, in the coordinate space of the
/// column that holds it. A plain vertical pass-through otherwise, so what it
/// reports is the geometry the real content would have been given.
private struct PlacementProbe: Layout {
  let recorder: PlacementRecorder
  let slot: PlacementSlot

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
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
    recorder.record(slot, bounds)
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
