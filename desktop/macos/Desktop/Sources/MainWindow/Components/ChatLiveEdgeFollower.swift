import AppKit
import SwiftUI

/// Damped follow of the transcript's live edge, driven by the display link.
///
/// `ScrollViewProxy.scrollTo` can only command a whole jump: every call sets the
/// offset outright. Following growing text with it means choosing between a step
/// at every line wrap and an animation that is retargeted before it lands, and
/// neither is smooth, because neither can move by a *fraction* of the distance.
///
/// A paced reveal makes that failure obvious. Between wraps the text grows
/// sideways and the offset does not change at all; at a wrap it changes by a
/// whole line at once. Commanded, that lands as a jolt — every line already on
/// screen moves 20 points in one frame.
///
/// So the offset is integrated instead of assigned: each frame it closes a
/// fixed fraction of the remaining distance. A wrap becomes an exponential ease
/// with no fixed duration to overrun, continuous growth is tracked with a
/// constant sub-pixel lag, and a burst is absorbed at the same shape as a single
/// line. There is nothing to retarget because there is no in-flight animation.
struct ChatLiveEdgeFollower: NSViewRepresentable {
  /// Whether the follow is running at all. Mounting stays cheap: an inactive
  /// follower holds its scroll view and does nothing.
  let isActive: Bool
  /// Re-read every frame, so the reader taking over is honoured on the next
  /// frame rather than at the end of some animation.
  let shouldFollow: () -> Bool

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.attach(to: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.shouldFollow = shouldFollow
    context.coordinator.setActive(isActive)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.setActive(false)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(shouldFollow: shouldFollow)
  }

  /// Fraction of the remaining distance closed per second, expressed as the
  /// time constant of the decay. At 0.08s a line wrap is ~63% absorbed after
  /// 80ms and visually settled inside 250ms — quick enough to keep the newest
  /// line in view, slow enough that the lines above it glide rather than jump.
  nonisolated static let timeConstant: CFTimeInterval = 0.08

  /// Below this the remaining distance is not worth another frame, and leaving
  /// it un-snapped would park the transcript a hair off the live edge — which
  /// the at-bottom test would then read as the reader having scrolled away.
  nonisolated static let snapThreshold: CGFloat = 0.5

  /// One integration step. Pure so the decay can be tested without a window:
  /// it must converge, never overshoot, and never move backwards.
  nonisolated static func stepped(
    from current: CGFloat, toward target: CGFloat, dt: CFTimeInterval
  ) -> CGFloat {
    let distance = target - current
    guard abs(distance) >= snapThreshold else { return target }
    // Clamped so a descheduled app resumes by gliding rather than teleporting.
    let clampedDt = min(0.1, max(0, dt))
    let progress = 1 - exp(-clampedDt / timeConstant)
    return current + distance * progress
  }

  @MainActor
  final class Coordinator: NSObject {
    var shouldFollow: () -> Bool
    private weak var scrollView: NSScrollView?
    private weak var hostView: NSView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(shouldFollow: @escaping () -> Bool) {
      self.shouldFollow = shouldFollow
    }

    func attach(to view: NSView) {
      hostView = view
      // The representable's view is installed as a background of the scroll
      // content, so the enclosing scroll view is up the superview chain — but
      // not until SwiftUI has placed it.
      DispatchQueue.main.async { [weak self] in
        self?.resolveScrollView()
      }
    }

    private func resolveScrollView() {
      var current: NSView? = hostView
      while let view = current {
        if let found = view as? NSScrollView {
          scrollView = found
          return
        }
        current = view.superview
      }
    }

    func setActive(_ active: Bool) {
      guard active else {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        return
      }
      guard displayLink == nil, let hostView else { return }
      if scrollView == nil { resolveScrollView() }
      let link = hostView.displayLink(target: self, selector: #selector(tick(_:)))
      link.add(to: .main, forMode: .common)
      displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
      let now = link.timestamp
      defer { lastTimestamp = now }
      guard let last = lastTimestamp else { return }
      guard shouldFollow() else { return }
      if scrollView == nil { resolveScrollView() }
      guard let scrollView, let documentView = scrollView.documentView else { return }

      let clipView = scrollView.contentView
      let maxOffset = documentView.frame.height - clipView.bounds.height
      // A document shorter than its viewport has no live edge to follow.
      guard maxOffset > 0 else { return }

      let current = clipView.bounds.origin.y
      guard current < maxOffset - ChatLiveEdgeFollower.snapThreshold else { return }

      let next = ChatLiveEdgeFollower.stepped(from: current, toward: maxOffset, dt: now - last)
      clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: next))
      scrollView.reflectScrolledClipView(clipView)
    }

    deinit {
      MainActor.assumeIsolated {
        displayLink?.invalidate()
      }
    }
  }
}
