import SwiftUI

/// Proportions of the Omi dotted-ring mark, shared by the two things that draw
/// it: `NotchOmiMark` and `OrbModel`'s resting ring. One source so the orb's
/// ring genuinely *is* the logo — with a literal in each, they drift silently
/// and the mark that travels into the orb slot changes shape on the way.
enum NotchMarkGeometry {
  static let dotCount = 8
  static let dotDiameterRatio: CGFloat = 0.18
  static let ringRadiusRatio: CGFloat = 0.33
  /// Start angle, so the ring at rest lands in the same rotation in both.
  static let startAngle: Double = -.pi

  /// Center of mark `index` on a ring of `radius` around `center`.
  static func ringPoint(index: Int, center: CGPoint, radius: CGFloat, rotation: Double = 0) -> CGPoint {
    let angle = 2 * Double.pi * Double(index) / Double(dotCount) + startAngle + rotation
    return CGPoint(
      x: center.x + radius * CGFloat(cos(angle)),
      y: center.y + radius * CGFloat(sin(angle))
    )
  }
}

/// The Omi dotted-ring mark. Dot colors default to white; agent surfaces tint
/// them by agent status.
struct NotchOmiMark: View {
  var dotColors: [Color] = []

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      let center = CGPoint(
        x: geometry.size.width / 2,
        y: geometry.size.height / 2
      )
      let dotDiameter = size * NotchMarkGeometry.dotDiameterRatio
      let ringRadius = size * NotchMarkGeometry.ringRadiusRatio

      ZStack {
        ForEach(0..<NotchMarkGeometry.dotCount, id: \.self) { index in
          let point = NotchMarkGeometry.ringPoint(index: index, center: center, radius: ringRadius)
          Circle()
            .fill(dotColors.indices.contains(index) ? dotColors[index] : Color.white.opacity(0.96))
            .frame(width: dotDiameter, height: dotDiameter)
            .position(x: point.x, y: point.y)
        }
      }
    }
    .drawingGroup(opaque: false, colorMode: .linear)
    .accessibilityHidden(true)
  }
}
