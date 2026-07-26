import SwiftUI

/// Every dot's opacity on the resting ring. File scope rather than a static on
/// the model, so `DotFrame`'s memberwise default is not actor-isolated.
private let chatMarkRestingOpacity = 0.95

/// What omi is doing with a turn, as the mark reads it. The two motions are
/// deliberately opposite: work that takes something in condenses, work that
/// puts something out unspools.
enum ChatMarkMotion: Equatable {
  /// Reading, searching, thinking: the ring condenses to a knot and blooms open.
  case gather
  /// Writing, running, delegating: the ring unspools into a travelling wave.
  case wave

  /// Seconds for one full pass. Both start and end on the full ring, which is
  /// what lets the mark change motion at a cycle boundary without a cut.
  var cycle: Double {
    switch self {
    case .gather: return 1.6
    case .wave: return 2.4
    }
  }

  /// Extra spin, in radians per second, at full working intensity.
  var spin: Double {
    switch self {
    case .gather: return 1.2
    case .wave: return 0.6
    }
  }

  /// Which motion a tool call belongs to. Tools that put something into the
  /// world are enumerated; everything else, including plain thinking and any
  /// tool we do not recognize, takes the quieter gather.
  static func forTool(_ toolName: String) -> ChatMarkMotion {
    let cleaned =
      toolName.hasPrefix("mcp__")
      ? String(toolName.split(separator: "__").last ?? Substring(toolName))
      : toolName
    let lower = cleaned.lowercased()
    let head =
      lower.split(separator: ":").first.map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? lower

    let acting: Set<String> = [
      "write", "edit", "multiedit", "notebookedit", "bash",
      "spawn_agent", "run_agent_and_wait", "send_agent_message", "run_attempt",
    ]
    return acting.contains(head) ? .wave : .gather
  }
}

/// Omi's mark at the foot of the chat transcript, as one element for the whole
/// life of the surface. It is never mounted and unmounted around a turn: at
/// rest it is the logo turning slowly, the same lap the landing hero makes, and
/// while omi works it takes up whichever motion the current work calls for.
///
/// The same 8 dots carry every state, and every state resolves to the ring, so
/// the logo is legible at all times. A motion only ever changes at a cycle
/// boundary, where both motions are the ring, so a turn that reads a file and
/// then writes one flows through the ring rather than cutting mid-shape.
///
/// Drawn through one `Canvas` on a `TimelineView` clock, the way the notch orb
/// is, rather than as 8 animated SwiftUI views: the motions need per-frame
/// per-dot geometry, which view modifiers cannot express without thrashing.
struct ChatOmiMark: View {
  /// Where the ring sits in the box the wave needs to unspool into.
  enum Anchor {
    /// The ring's left edge lands on the container's leading edge and the wave
    /// grows rightward only. What the transcript wants, so the mark shares a
    /// vertical with the message text.
    case leading
    /// The ring sits in the middle and the wave unspools symmetrically. What a
    /// centered lockup wants, such as the window's identity.
    case centered
  }

  var motion: ChatMarkMotion?
  var size: CGFloat = 30
  var anchor: Anchor = .leading

  @State private var model = ChatMarkModel()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isWorking: Bool { motion != nil }

  var body: some View {
    // The resting lap takes 18 seconds, so it does not need a vsync clock; a
    // transcript sits open for hours and this mark never leaves it.
    TimelineView(
      .animation(minimumInterval: isWorking ? nil : 1.0 / 20.0, paused: reduceMotion)
    ) { timeline in
      Canvas { context, canvasSize in
        model.advance(
          to: timeline.date,
          motion: motion,
          reduceMotion: reduceMotion
        )
        model.draw(into: &context, size: canvasSize, base: size, anchor: anchor)
      }
    }
    // Wide enough for the wave to unspool into, tall enough for the ring.
    .frame(width: size * ChatMarkModel.widthRatio, height: size)
    // Leading anchoring pulls the ring's left edge out to the container's, so
    // the mark does not float inboard of the text (see ChatMarkModel.centerX).
    .padding(.leading, anchor == .leading ? -size * ChatMarkModel.leftAnchor : 0)
    .accessibilityHidden(true)
  }
}

/// Per-frame state for `ChatOmiMark`: an accumulating rotation, an `intensity`
/// scalar easing between resting and working, and a position within the current
/// motion's cycle.
@MainActor
final class ChatMarkModel {
  private static let count = NotchMarkGeometry.dotCount
  /// Resting spin, in radians per second — one lap per 18s, matching the
  /// landing hero so the mark reads as the same object on both surfaces.
  private static let restingSpin: Double = 2 * .pi / 18

  /// Canvas width as a multiple of the mark size, sized for the unspooled wave.
  static let widthRatio: CGFloat = 1.7
  /// Ring centre, as a fraction of the mark size from the canvas's left edge.
  /// The ring's own radius plus a dot radius is 0.42, so a centre at 0.55
  /// leaves the ring's left edge at 0.13 with room for the bloom's overshoot.
  static let centerX: CGFloat = 0.55
  /// Where the ring's left edge sits, and where the unspooled line begins, so
  /// resting and working share one left vertical.
  static let leftAnchor: CGFloat = 0.13

  private var rotation: Double = 0
  private var intensity: Double = 0
  private var phase: Double = 0
  private var motion: ChatMarkMotion = .gather
  /// A motion requested mid-cycle. Applied at the next wrap, never immediately:
  /// switching while the ring is a knot or a line would cut the shape in half.
  private var pendingMotion: ChatMarkMotion?
  private var wasWorking = false
  private var lastTime: CFTimeInterval?

  func advance(to date: Date, motion requested: ChatMarkMotion?, reduceMotion: Bool) {
    let now = date.timeIntervalSinceReferenceDate
    let dt = lastTime.map { min(0.05, max(0, now - $0)) } ?? (1.0 / 60.0)
    lastTime = now

    let working = requested != nil && !reduceMotion

    if let requested {
      if !wasWorking {
        // A turn opens on the ring, so its first cycle is whole.
        motion = requested
        pendingMotion = nil
        phase = 0
      } else if requested != motion {
        pendingMotion = requested
      } else {
        pendingMotion = nil
      }
    }
    wasWorking = working

    // Intensity is eased, never switched: a finished turn has to let the ring
    // wind down into its resting lap instead of cutting to it.
    intensity += ((working ? 1 : 0) - intensity) * min(1, dt * 3.2)

    rotation += dt * (Self.restingSpin + motion.spin * intensity)

    guard intensity > 0.001 else {
      // Settled back to rest; the next turn starts clean.
      phase = 0
      return
    }
    phase += dt / motion.cycle
    if phase >= 1 {
      phase -= 1
      if let pendingMotion {
        motion = pendingMotion
        self.pendingMotion = nil
      }
    }
  }

  func draw(
    into context: inout GraphicsContext,
    size: CGSize,
    base: CGFloat,
    anchor: ChatOmiMark.Anchor
  ) {
    let dotDiameter = base * NotchMarkGeometry.dotDiameterRatio
    let ringRadius = base * NotchMarkGeometry.ringRadiusRatio
    let centerY = size.height / 2

    // Leading: the ring is pushed left so its edge can meet the text vertical,
    // and the line starts there too. Centered: both are symmetric about the box.
    let centerX = anchor == .leading ? base * Self.centerX : size.width / 2
    let lineStart =
      anchor == .leading
      ? base * Self.leftAnchor + dotDiameter / 2
      : dotDiameter / 2
    let lineEnd = size.width - dotDiameter / 2
    let lineStep = (lineEnd - lineStart) / CGFloat(Self.count - 1)

    for index in 0..<Self.count {
      let f = frame(dot: index)
      let angle =
        2 * Double.pi * Double(index) / Double(Self.count)
        + NotchMarkGeometry.startAngle + rotation
      let ringX = centerX + ringRadius * CGFloat(f.radiusX) * CGFloat(cos(angle))
      let ringY = centerY + ringRadius * CGFloat(f.radiusY) * CGFloat(sin(angle))
      let lineX = lineStart + lineStep * CGFloat(index)

      let x = ringX + (lineX - ringX) * CGFloat(f.line)
      let y = ringY + (centerY - ringY) * CGFloat(f.line) + base * CGFloat(f.offsetY)

      let diameter = dotDiameter * CGFloat(f.scale)
      let rect = CGRect(
        x: x - diameter / 2,
        y: y - diameter / 2,
        width: diameter,
        height: diameter
      )
      context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(f.opacity)))
    }
  }

  // MARK: - Motion curves

  private struct DotFrame {
    var radiusX: Double = 1
    var radiusY: Double = 1
    var scale: Double = 1
    var opacity: Double = chatMarkRestingOpacity
    var line: Double = 0
    var offsetY: Double = 0
  }

  /// The resting ring blended toward the current motion by `intensity`, so a
  /// turn starting or ending is a ramp rather than a jump.
  private func frame(dot index: Int) -> DotFrame {
    guard intensity > 0.001 else { return DotFrame() }
    let working = motion == .gather ? gather(dot: index) : wave(dot: index)
    let t = intensity
    return DotFrame(
      radiusX: 1 + (working.radiusX - 1) * t,
      radiusY: 1 + (working.radiusY - 1) * t,
      scale: 1 + (working.scale - 1) * t,
      opacity: chatMarkRestingOpacity + (working.opacity - chatMarkRestingOpacity) * t,
      line: working.line * t,
      offsetY: working.offsetY * t
    )
  }

  /// Condense to a knot, hold, spring open. Lands rotated, because the rotation
  /// keeps accumulating while the dots are gathered.
  private func gather(dot index: Int) -> DotFrame {
    if phase < 0.45 {
      let u = Self.easeInOut(phase / 0.45)
      return DotFrame(
        radiusX: 1 - 0.68 * u, radiusY: 1 - 0.68 * u,
        scale: 1 + 0.24 * u, opacity: 0.62 + 0.38 * u
      )
    }
    if phase < 0.55 {
      return DotFrame(radiusX: 0.32, radiusY: 0.32, scale: 1.24, opacity: 1)
    }
    let u = (phase - 0.55) / 0.45
    let r = 0.32 + 0.68 * Self.easeOutBack(u)
    return DotFrame(
      radiusX: r, radiusY: r,
      scale: 1.24 - 0.24 * Self.easeInOut(u), opacity: 1
    )
  }

  /// Unspool into a travelling wave, run, refold. The line begins at the same
  /// left vertical the ring rests on, so the mark grows rightward only.
  private func wave(dot index: Int) -> DotFrame {
    let line = Self.bump(phase, up: 0.30, down: 0.72)
    let travel = sin(2 * .pi * phase * 2 - Double(index) * 0.9)
    return DotFrame(
      scale: 1,
      opacity: 0.55 + 0.42 * (0.5 + 0.5 * travel),
      line: line,
      offsetY: 0.13 * travel * line
    )
  }

  // MARK: - Easing

  private static func easeInOut(_ t: Double) -> Double {
    t * t * (3 - 2 * t)
  }

  /// Overshoots slightly past 1 so the bloom springs rather than eases. The
  /// overshoot is bounded so the dots stay inside the frame.
  private static func easeOutBack(_ t: Double) -> Double {
    let c1 = 1.70158
    let c3 = c1 + 1
    let p = t - 1
    return 1 + c3 * p * p * p + c1 * p * p
  }

  /// 0 → 1 → 0 across the cycle, eased at both ends and flat between.
  private static func bump(_ t: Double, up: Double, down: Double) -> Double {
    if t < up { return easeInOut(t / up) }
    if t < down { return 1 }
    return 1 - easeInOut((t - down) / (1 - down))
  }
}
