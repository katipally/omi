import OmiTheme
import SwiftUI

struct OmiThinkingMark: View {
  @State private var angle: Double = 0

  private static let dotCount = 8
  private static let dotDiameterRatio: CGFloat = 0.18
  private static let ringRadiusRatio: CGFloat = 0.33
  private static let trail: [Color] = (0..<dotCount).map { index in
    Color.white.opacity(1.0 - Double(index) * 0.1)
  }

  var body: some View {
    omiMark(dotColors: Self.trail)
      .rotationEffect(.degrees(angle))
      .onAppear {
        angle = 0
        OmiMotion.withGated(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
          angle = 360
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Thinking")
  }

  private func omiMark(dotColors: [Color]) -> some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      let center = CGPoint(
        x: geometry.size.width / 2,
        y: geometry.size.height / 2
      )
      let dotDiameter = size * Self.dotDiameterRatio
      let ringRadius = size * Self.ringRadiusRatio

      ZStack {
        ForEach(0..<Self.dotCount, id: \.self) { index in
          let angle = Double(index) / Double(Self.dotCount) * Double.pi * 2 - Double.pi
          Circle()
            .fill(dotColors.indices.contains(index) ? dotColors[index] : Color.white.opacity(0.96))
            .frame(width: dotDiameter, height: dotDiameter)
            .position(
              x: center.x + CGFloat(cos(angle)) * ringRadius,
              y: center.y + CGFloat(sin(angle)) * ringRadius
            )
        }
      }
    }
    .drawingGroup(opaque: false, colorMode: .linear)
    .accessibilityHidden(true)
  }
}

struct TypingIndicator: View {
  var body: some View {
    OmiThinkingMark()
      .frame(width: 24, height: 24)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(OmiColors.backgroundTertiary)
      .clipShape(RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous))
  }
}

// MARK: - Working status

/// The status line shown under the transcript while omi works on a turn.
/// An in-flight tool names itself so the reader sees what omi is actually
/// doing; with no tool running the turn is still composing a reply.
enum ChatWorkingStatus {
  static let idleLabel = "Thinking"

  static func label(for message: ChatMessage?) -> String {
    guard let name = inFlightToolName(for: message) else { return idleLabel }
    return ChatContentBlock.displayName(for: name)
  }

  /// Which way the mark moves for this turn. Plain thinking condenses, like the
  /// reading tools do; only work that puts something out unspools.
  static func motion(for message: ChatMessage?) -> ChatMarkMotion {
    guard let name = inFlightToolName(for: message) else { return .gather }
    return ChatMarkMotion.forTool(name)
  }

  private static func inFlightToolName(for message: ChatMessage?) -> String? {
    guard let message, message.sender == .ai else { return nil }
    let inFlight = message.contentBlocks.last { block in
      if case .toolCall(_, _, let status, _, _, _) = block { return status.isInFlight }
      return false
    }
    guard case .toolCall(_, let name, _, _, _, _) = inFlight else { return nil }
    return name
  }
}

/// The foot of the transcript: omi's mark, and the status label beside it while
/// a turn is open. The mark is permanent — it turns slowly at rest and takes up
/// a working motion when there is work — so it reads as omi being present
/// rather than as a spinner that appears and vanishes.
struct ChatWorkingIndicator: View {
  /// The live status line. `nil` means no turn is open, so the mark rests and
  /// the label is absent.
  let label: String?
  let motion: ChatMarkMotion

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      ChatOmiMark(motion: label == nil ? nil : motion)

      if let label {
        ShimmeringLabel(text: label)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .omiAnimation(.easeOut(duration: 0.2), value: label == nil)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label ?? "Omi")
    .accessibilityHidden(label == nil)
  }
}

/// A highlight sweeping left to right through the glyphs. The gradient is
/// masked by a second copy of the same text, so it lights the letters instead
/// of a rectangle behind them.
private struct ShimmeringLabel: View {
  let text: String

  @State private var travel: CGFloat = 0

  var body: some View {
    Text(text)
      .scaledFont(size: OmiType.subheading, weight: .medium)
      .foregroundStyle(OmiColors.textQuaternary)
      .overlay {
        GeometryReader { proxy in
          let width = max(proxy.size.width, 1)
          let bandWidth = width * 0.7
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: OmiColors.textPrimary, location: 0.5),
              .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: bandWidth)
          .offset(x: -bandWidth + travel * (width + bandWidth))
        }
        .mask {
          Text(text)
            .scaledFont(size: OmiType.subheading, weight: .medium)
        }
        .allowsHitTesting(false)
      }
      .onAppear {
        guard !OmiMotion.reduceMotion else { return }
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
          travel = 1
        }
      }
  }
}
