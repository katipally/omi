import SwiftUI

/// The Omi identity, as one element for the whole life of a panel. The same 8
/// marks morph between two layouts and never cross-fade:
/// - listening / speaking: a horizontal audio waveform (the 8 marks become
///   bars that bounce to the mic level while you talk, and to the TTS output
///   level while Omi speaks);
/// - thinking: the 8 marks are the Omi dot-ring, rotating;
/// - logo: the same dot-ring at rest — the mark in the closed notch chrome, and
///   what a finished reply lingers under.
///
/// Rendered once (a persistent layer in `NotchView`) so switching phase morphs
/// in place rather than swapping views, and so the mark can travel between the
/// chrome lobe and the orb slot without ever being two separate logos.
struct NotchVoiceOrb: View {
  enum Mode: Equatable { case listening, thinking, speaking, logo }
  let mode: Mode

  /// Full-scale reference per source, so one response curve serves both. The
  /// capture service publishes raw speech RMS, which is tiny — measured at
  /// ~0.001–0.004 for ordinary talking — while the TTS player pre-scales its own
  /// by 3.5 before publishing. Normalizing against one shared number is what
  /// left the listening waveform pinned to its idle floor.
  static let micFullScale: CGFloat = 0.02
  static let playbackFullScale: CGFloat = 0.5
  /// Per-dot tint for the resting ring (ambient agent status). Empty = white.
  var dotColors: [Color] = []

  @State private var model = OrbModel()
  /// The Canvas needs a per-frame clock only while something is moving. At rest
  /// the mark is a static ring, and every panel holds one for the whole session
  /// — an always-live timeline would put idle CPU on every display.
  @State private var isAnimating = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: !isAnimating)) { timeline in
      Canvas { context, size in
        let level: CGFloat
        switch mode {
        // Each source normalized against its own full scale (see above), so the
        // curve below reads the same 0...1 whichever is driving the waveform.
        case .listening:
          level = CGFloat(AudioLevelMonitor.shared.instantMicrophoneLevel) / Self.micFullScale
        case .speaking:
          level = CGFloat(AudioLevelMonitor.shared.playbackLevel) / Self.playbackFullScale
        case .thinking, .logo: level = 0
        }
        model.advance(to: timeline.date, level: level, mode: mode, reduceMotion: reduceMotion)
        model.draw(into: &context, size: size, dotColors: dotColors)
      }
    }
    // Every mode change re-arms the clock. Only `.logo` ever settles, and only
    // after the springs and the bars->ring morph have run out; the others are
    // driven by live audio or a rotation and never stop on their own.
    .task(id: mode) {
      isAnimating = true
      guard mode == .logo else { return }
      try? await Task.sleep(for: .seconds(1.2))
      guard !Task.isCancelled else { return }
      isAnimating = false
    }
    .accessibilityHidden(true)
  }
}

/// Per-frame state for `NotchVoiceOrb`: 8 marks that spring toward an audio
/// target (waveform), a `morph` scalar (0 = ring, 1 = bars) that eases on mode
/// change, and a rotation accumulator used only while it is a spinning ring.
@MainActor
final class OrbModel {
  private static let count = 8

  private var values = [CGFloat](repeating: 0, count: count)
  private var velocities = [Double](repeating: 0, count: count)
  private var morph: CGFloat = 0
  private var rotation: Double = 0
  private var spinning = false
  private var lastTime: CFTimeInterval?

  private let phases: [Double] = (0..<count).map { Double($0) * 1.9 }
  private let speeds: [Double] = (0..<count).map { 6.0 + 2.5 * sin(Double($0) * 1.3) }

  // Underdamped spring -> visible bounce (same feel as VoiceWaveformBars).
  private let stiffness: Double = 200
  private let damping: Double = 10

  func advance(to date: Date, level: CGFloat, mode: NotchVoiceOrb.Mode, reduceMotion: Bool) {
    let now = date.timeIntervalSinceReferenceDate
    let dt = lastTime.map { min(0.032, max(0.0, now - $0)) } ?? (1.0 / 60.0)
    lastTime = now

    let bars = mode == .listening || mode == .speaking
    let morphTarget: CGFloat = bars ? 1 : 0
    // Ease the layout morph so the logo ring visibly stretches into the
    // waveform (and back); snap when reduced motion is on.
    morph += (morphTarget - morph) * CGFloat(reduceMotion ? 1 : min(1, dt * 5))
    spinning = mode == .thinking
    rotation += (spinning && !reduceMotion) ? dt * 2.2 : 0

    // A fixed response curve, not a running-peak normalizer. Dividing by a peak
    // follower made a whisper and a shout draw the same waveform, and its floor
    // gate sat above ordinary speech RMS — so the listening bars answered the
    // idle sine and nothing else, and you got no signal that Omi could hear you.
    let lvl = Double(max(0, level))
    let gained = min(1.0, pow(lvl, 0.6))

    for i in 0..<Self.count {
      let target: Double
      if bars {
        // A calm voice waveform, not a party visualizer: the idle floor keeps
        // the bars alive at silence and the wobble only varies the peaks, so
        // loudness still reads through.
        let idle = 0.10 + 0.07 * (0.5 + 0.5 * sin(now * speeds[i] + phases[i]))
        let wobble = 0.72 + 0.28 * sin(now * speeds[i] + phases[i])
        target = max(idle, min(0.9, gained * wobble))
      } else {
        target = 0
      }
      let x = Double(values[i])
      let accel = stiffness * (target - x) - damping * velocities[i]
      velocities[i] += accel * dt
      values[i] = CGFloat(max(0.0, min(1.0, x + velocities[i] * dt)))
    }
  }

  func draw(into context: inout GraphicsContext, size: CGSize, dotColors: [Color] = []) {
    let n = Self.count
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    // Ring sized off height so it reads as the Omi logo regardless of the wide
    // canvas the waveform needs. Proportions come from NotchMarkGeometry, the
    // same source the static mark uses, so the ring IS the logo.
    let ringRadius = size.height * NotchMarkGeometry.ringRadiusRatio
    let dotDiameter = size.height * NotchMarkGeometry.dotDiameterRatio

    let span = size.width * 0.84
    let step = span / CGFloat(n)
    let barWidth = min(step * 0.5, 4.5)
    let minBarH = barWidth
    let maxBarH = size.height * 0.66
    let barStartX = (size.width - span) / 2 + step / 2

    for i in 0..<n {
      let ringPoint = NotchMarkGeometry.ringPoint(
        index: i, center: center, radius: ringRadius, rotation: rotation)
      let barPoint = CGPoint(x: barStartX + step * CGFloat(i), y: center.y)
      let point = lerp(ringPoint, barPoint, morph)

      let barH = minBarH + (maxBarH - minBarH) * values[i]
      let markW = lerp(dotDiameter, barWidth, morph)
      let markH = lerp(dotDiameter, barH, morph)

      // At rest the ring is the Omi logo: 8 equal white dots. Only the spinning
      // "thinking" ring gets a leading trail so the rotation reads.
      let ringOpacity = spinning ? 0.62 + 0.38 * (1.0 - Double(i) / Double(n)) : 0.95
      let opacity = lerp(CGFloat(ringOpacity), 1, morph)

      // Ambient agent status. The caller withholds colors during a voice turn:
      // a waveform tracking live audio is not where a background job's health
      // should be read.
      let tint = dotColors.indices.contains(i) ? dotColors[i] : .white
      let rect = CGRect(
        x: point.x - markW / 2, y: point.y - markH / 2, width: markW, height: markH)
      context.fill(
        Path(roundedRect: rect, cornerRadius: markW / 2),
        with: .color(tint.opacity(Double(opacity)))
      )
    }
  }

  private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
  private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
  }
}
