import AppKit
import SwiftUI

/// The notch's animation springs — single source of truth so every call site
/// stays in step. The discrete morph rides these; continuous height growth
/// rides its own `.smooth` timeline in NotchView and must never merge with
/// them: keying the morph spring on a measured height makes the
/// measure -> resize -> remeasure loop oscillate.
///
/// These are raw, not `OmiMotion.gated`. Reduce Motion is honored one level up,
/// where `NotchView` swaps the whole timeline for a short ease and
/// `NotchScreenManager` routes its imperative calls through `OmiMotion`. Gating
/// here would return nil and make a panel that grows out of the camera housing
/// snap to size instead of cross-fading, which reads as a glitch.
enum NotchAnimation {
  static let open = Animation.spring(response: 0.40, dampingFraction: 0.78)
  static let close = Animation.spring(response: 0.34, dampingFraction: 0.9)
  /// Reduce Motion substitute: still a transition, just no spring overshoot.
  static let reduced = Animation.easeInOut(duration: 0.25)
}

/// Single source of truth for the notch's fixed geometry.
enum NotchMetrics {
  /// Floor for the closed chrome height where there is no physical notch to
  /// measure. Width is never a fallback: every display straddles a dead zone.
  static let fallbackClosedHeight: CGFloat = 34
  /// The camera dead zone assumed when a display has no measurable housing —
  /// an external monitor, or a notched one whose auxiliary areas read empty.
  /// Displays without a camera still reserve it, so the closed notch keeps the
  /// same proportions everywhere instead of collapsing to a floating cluster.
  static let fallbackHiddenCenterWidth: CGFloat = 172
  /// Padding added around the measured camera gap so chrome never touches it.
  static let hiddenCenterSafetyPadding: CGFloat = 34
  /// Width of each chrome lobe flanking the camera: omi logo (left), settings
  /// gear (right) — always visible in the closed state.
  static let closedSideWidth: CGFloat = 30
  /// Extra width the hint strip takes over the closed notch.
  static let hintExtraWidth: CGFloat = 100
  /// Readable status strip under the chrome for too-short PTT / mic errors.
  /// The floor the measured strip clamps up to, so a one-word hint still reads
  /// as a strip rather than a hairline.
  static let hintRowHeight: CGFloat = 30
  /// Ceiling for the measured hint strip. A hint is a status line, not a
  /// paragraph; past this the text truncates instead of growing the notch.
  static let hintMaxHeight: CGFloat = 78
  /// Retired: the proactive card is measured now, so nothing derives a panel
  /// size from this pair. It stays in-tree so its removal can be its own
  /// reviewable change.
  static let notificationSize = CGSize(width: 430, height: 108)
  /// The proactive card lays out at one fixed width across every variant —
  /// only the height follows the content, the same contract the voice body has.
  static let notificationWidth: CGFloat = 430
  /// Floor for the measured card. The single-line receipt is the shortest card
  /// there is; below this the panel reads as a sliver rather than a surface.
  static let notificationMinHeight: CGFloat = 42
  /// Ceiling for the measured card. Content is capped to fit inside it, so this
  /// is a guard against a runaway string, not a routine clamp.
  static let notificationMaxHeight: CGFloat = 220
  static let notificationSpacing: CGFloat = 8
  /// Horizontal inset every content surface owes the silhouette.
  ///
  /// `NotchShape` runs its vertical sides at `minX + topCornerRadius` and
  /// `maxX - topCornerRadius` — only the topmost band flares out to the full
  /// width. Content laid out to the panel's full width is therefore clipped by
  /// that radius on both edges, which is what cut the leading icon off the
  /// notification card. Anything inside the clip shape starts here.
  static var contentSideInset: CGFloat { cornerOpen.top }
  /// Slack around the content so the fixed window can hold glow bleed + shadow.
  static let shadowPadding: CGFloat = 22
  /// How far the panel extends *above* the display's top edge. The notch has to
  /// look welded to the bezel, and a window sitting exactly on the top edge
  /// leaves the topmost device pixel row to the desktop — a one-pixel seam of
  /// wallpaper above the black. Bleeding past the edge puts the boundary
  /// off-screen instead of trying to land on it exactly.
  static let topOverscan: CGFloat = 2
  /// Corner radii: (top, bottom) for the closed notch and an expanded surface.
  /// Shape geometry, not chrome — tuned against the physical camera housing,
  /// which is why these are not drawn from `OmiChrome`.
  static let cornerClosed: (top: CGFloat, bottom: CGFloat) = (6, 14)
  static let cornerOpen: (top: CGFloat, bottom: CGFloat) = (20, 26)

  // MARK: - Closed-size math (pure, injectable for tests)

  /// Whether a display exposes a real camera housing. Geometry no longer
  /// branches on this — every display reserves a dead zone — but it still
  /// selects whether the housing is *measured* or *synthesized*, which is what
  /// makes OMI_FORCE_NO_NOTCH a usable stand-in for an external monitor on a
  /// notched Mac. NO_NOTCH wins when both hooks are set.
  static func screenHasCameraHousing(_ screen: NSScreen?) -> Bool {
    if let forced = getenv("OMI_FORCE_NO_NOTCH"), String(cString: forced) == "1" { return false }
    if let forced = getenv("OMI_FORCE_NOTCH"), String(cString: forced) == "1" { return true }
    guard let screen else { return false }
    if let leftArea = screen.auxiliaryTopLeftArea,
      let rightArea = screen.auxiliaryTopRightArea,
      !leftArea.isEmpty,
      !rightArea.isEmpty
    {
      return true
    }
    return screen.safeAreaInsets.top > 0
  }

  /// The physical camera housing width alone (no safety padding) — what the
  /// chrome icons visually hug.
  static func cameraWidth(auxiliaryTopLeftArea: NSRect?, auxiliaryTopRightArea: NSRect?) -> CGFloat {
    if let leftArea = auxiliaryTopLeftArea,
      let rightArea = auxiliaryTopRightArea,
      !leftArea.isEmpty,
      !rightArea.isEmpty
    {
      let measuredGap = rightArea.minX - leftArea.maxX
      if measuredGap > 0 { return measuredGap }
    }
    return fallbackHiddenCenterWidth
  }

  /// The camera dead zone the chrome must straddle: the measured gap between
  /// the two auxiliary top areas plus safety padding.
  static func hiddenCenterWidth(auxiliaryTopLeftArea: NSRect?, auxiliaryTopRightArea: NSRect?) -> CGFloat {
    if let leftArea = auxiliaryTopLeftArea,
      let rightArea = auxiliaryTopRightArea,
      !leftArea.isEmpty,
      !rightArea.isEmpty
    {
      let measuredGap = rightArea.minX - leftArea.maxX
      if measuredGap > 0 {
        return max(fallbackHiddenCenterWidth + hiddenCenterSafetyPadding, measuredGap + hiddenCenterSafetyPadding)
      }
    }
    return fallbackHiddenCenterWidth + hiddenCenterSafetyPadding
  }

  /// Closed chrome height: the physical notch height when present, else the
  /// menu-bar strip height, floored at the fallback.
  static func closedHeight(topSafeAreaInset: CGFloat, frameMaxY: CGFloat, visibleFrameMaxY: CGFloat) -> CGFloat {
    if topSafeAreaInset > 0 { return topSafeAreaInset }
    return max(fallbackClosedHeight, frameMaxY - visibleFrameMaxY - 1)
  }

  /// The closed notch: camera dead zone flanked by the two always-visible
  /// chrome lobes (logo / gear).
  ///
  /// The dead zone is reserved on every display, measured where a housing
  /// exists and synthesized where none does. Height still differs — a notchless
  /// display's chrome covers the menu-bar strip, not a camera bump — but the
  /// horizontal proportions are identical, so the mark and gear land at the
  /// same offsets from center on a MacBook and an external monitor alike.
  static func closedSize(
    auxiliaryTopLeftArea: NSRect?,
    auxiliaryTopRightArea: NSRect?,
    topSafeAreaInset: CGFloat,
    frameMaxY: CGFloat,
    visibleFrameMaxY: CGFloat
  ) -> CGSize {
    let height = closedHeight(
      topSafeAreaInset: topSafeAreaInset, frameMaxY: frameMaxY, visibleFrameMaxY: visibleFrameMaxY)
    let center = hiddenCenterWidth(
      auxiliaryTopLeftArea: auxiliaryTopLeftArea, auxiliaryTopRightArea: auxiliaryTopRightArea)
    return CGSize(width: center + closedSideWidth * 2, height: height)
  }

  /// The housing measurements to size from. A display with no housing — or one
  /// forced to behave like it has none — reports nil so the dead zone is
  /// synthesized from `fallbackHiddenCenterWidth` instead.
  static func auxiliaryAreas(for screen: NSScreen) -> (left: NSRect?, right: NSRect?) {
    guard screenHasCameraHousing(screen) else { return (nil, nil) }
    return (screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea)
  }

  static func closedSize(for screen: NSScreen) -> CGSize {
    let areas = auxiliaryAreas(for: screen)
    return closedSize(
      auxiliaryTopLeftArea: areas.left,
      auxiliaryTopRightArea: areas.right,
      topSafeAreaInset: areas.left == nil ? 0 : screen.safeAreaInsets.top,
      frameMaxY: screen.frame.maxY,
      visibleFrameMaxY: screen.visibleFrame.maxY
    )
  }

  static func cameraWidth(for screen: NSScreen) -> CGFloat {
    let areas = auxiliaryAreas(for: screen)
    return cameraWidth(auxiliaryTopLeftArea: areas.left, auxiliaryTopRightArea: areas.right)
  }
}

extension NSScreen {
  var omiDisplayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
  }
}
