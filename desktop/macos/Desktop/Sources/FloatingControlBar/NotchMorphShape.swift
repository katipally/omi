import SwiftUI

/// The notch body outline. Square top corners blend into a physical notch/bezel;
/// a floating surface on a non-notched display rounds them instead. Radii are
/// animatable so the surface morphs smoothly as it grows from the camera housing.
struct NotchDockShape: Shape {
  var bottomRadius: CGFloat
  var topRadius: CGFloat = 0

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(bottomRadius, topRadius) }
    set {
      bottomRadius = newValue.first
      topRadius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let radius = min(bottomRadius, rect.height / 2)
    let topR = min(topRadius, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + topR),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + topR, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }
}

/// Lower-edge / full-perimeter outline used for the notch surface glow.
struct NotchLowerEdgeShape: Shape {
  var bottomRadius: CGFloat
  /// 0 = open lower-edge path (notch mode: the top blends into the bezel).
  /// > 0 = closed full-perimeter ring with rounded top corners (pill mode:
  /// the surface is a floating card, so the glow wraps all the way around).
  var topRadius: CGFloat = 0
  /// Inset from the shape bounds. Pill-mode windows have no glow outsets,
  /// so the ring is drawn slightly inside the surface to avoid clipping.
  var edgeInset: CGFloat = 0

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(bottomRadius, topRadius) }
    set {
      bottomRadius = newValue.first
      topRadius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: edgeInset, dy: edgeInset)
    let radius = min(max(0, bottomRadius - edgeInset), rect.height / 2)
    var path = Path()
    if topRadius > 0 {
      let topR = min(max(0, topRadius - edgeInset), rect.height / 2)
      path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + topR),
        control: CGPoint(x: rect.maxX, y: rect.minY)
      )
    } else {
      path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    if topRadius > 0 {
      let topR = min(max(0, topRadius - edgeInset), rect.height / 2)
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX + topR, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY)
      )
      path.closeSubpath()
    } else {
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 1))
    }
    return path
  }
}
