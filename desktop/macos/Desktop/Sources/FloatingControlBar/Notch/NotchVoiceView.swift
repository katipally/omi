import OmiTheme
import SwiftUI

/// The expanded voice content below the morphing Omi orb.
///
/// Listening shows a clean "Listening…" caption: the STT providers in use don't
/// reliably emit partial transcripts during a hold, so a live transcript would
/// appear for some setups and blank for others. The words show up in the reply
/// phase instead.
///
/// Responding reveals Omi's reply at the speaking cadence. Reports its measured
/// height so the panel grows as lines wrap (fixed width, capped at 40% of the
/// screen); longer content scrolls and auto-follows the newest line. Tapping the
/// reply opens the full conversation in the app.
struct NotchVoiceView: View {
  /// Omi's reply. Empty while listening.
  var text: String = ""
  /// Caption shown while listening.
  var placeholder: String = ""
  /// Non-nil for the reply: tapping opens the main window.
  let onOpenApp: (() -> Void)?
  /// True while the reply is still streaming (drives the tap-hint timing).
  let followsTail: Bool
  /// Vertical space reserved at the top for the camera housing + the orb.
  let topReserve: CGFloat
  /// The panel's max height; auto-scroll only engages once content overflows it.
  let maxBodyHeight: CGFloat
  let onHeightChange: (CGFloat) -> Void

  @State private var lastContentHeight: CGFloat = 0

  private var isReply: Bool { onOpenApp != nil }
  /// The tap hint only appears once a reply has settled (not while streaming).
  private var showsOpenHint: Bool { isReply && !followsTail && !text.isEmpty }
  private var hintHeight: CGFloat { showsOpenHint ? 26 : 0 }

  var body: some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: topReserve)
      ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: true) {
          VStack(spacing: 0) {
            transcript
              .padding(.horizontal, 30)
              .padding(.bottom, OmiSpacing.md)
              .id("voiceTop")
            Color.clear.frame(height: 1).id("voiceBottom")
          }
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: { height in
            onHeightChange(topReserve + height + hintHeight)
            // Only follow the newest line once content actually overflows the
            // cap. Below the cap the panel grows to fit, so scrolling then
            // would fight the grow animation and read as a flicker.
            let overflowing = topReserve + height + hintHeight >= maxBodyHeight - 1
            if overflowing, height > lastContentHeight + 1 {
              withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("voiceBottom", anchor: .bottom) }
            }
            lastContentHeight = height
          }
        }
      }
      if showsOpenHint {
        openHint.transition(.opacity)
      }
    }
    .omiAnimation(.easeInOut(duration: 0.2), value: showsOpenHint)
  }

  @ViewBuilder
  private var transcript: some View {
    if text.isEmpty && isReply {
      // Reply is starting (audio can lead the first text token); the speaking
      // orb carries it until words arrive.
      Color.clear.frame(height: 1)
    } else {
      content
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onOpenApp?() }
        .accessibilityAddTraits(isReply ? .isButton : [])
    }
  }

  @ViewBuilder
  private var content: some View {
    if isReply {
      // Omi's reply: paced to the speaking cadence, justified. The shimmer is
      // the "still arriving" signal, so it stops the moment the reply settles —
      // otherwise it runs a 60fps timeline over static text for as long as the
      // user keeps the pointer on the notch.
      StreamingReplyText(fullText: text, size: OmiType.body, opacity: 0.9)
        .shimmer(active: followsTail)
    } else {
      Text(placeholder)
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundStyle(.white.opacity(0.6))
        .shimmer()
    }
  }

  private var openHint: some View {
    Button(action: { onOpenApp?() }) {
      HStack(spacing: 3) {
        Text("Open in Omi")
        Image(systemName: "arrow.up.forward")
          .scaledFont(size: 9, weight: .semibold)
      }
      .scaledFont(size: OmiType.micro, weight: .medium)
      .foregroundStyle(.white.opacity(0.45))
      .padding(.vertical, OmiSpacing.xs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open the full conversation in Omi")
  }
}

// MARK: - Shimmer

extension View {
  /// A slow light sweep across the glyphs — the "live / streaming" shimmer used
  /// on the voice-state text. No-op under reduced motion, and no-op when
  /// inactive so a settled reply costs nothing.
  func shimmer(active: Bool = true) -> some View { modifier(ShimmerModifier(active: active)) }
}

private struct ShimmerModifier: ViewModifier {
  let active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion || !active {
      content
    } else {
      content.overlay {
        GeometryReader { geo in
          TimelineView(.animation) { timeline in
            let period = 2.2
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            let travel = geo.size.width + 160
            let x = CGFloat(t / period) * travel - 80
            LinearGradient(
              colors: [.clear, .white.opacity(0.85), .clear],
              startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 80)
            .offset(x: x)
            .blendMode(.plusLighter)
          }
        }
        .mask(content)
        .allowsHitTesting(false)
      }
    }
  }
}
