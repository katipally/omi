import AppKit
import OmiTheme
import SwiftUI

/// The Home landing: the centered hero and prompt chips Home opens on, before
/// the transcript. Presentation only — the conversation underneath is the same
/// one shared thread, and the first send transitions the stage to `.chat`.
///
/// Kept out of `DashboardPage` so the landing can grow without pushing that
/// file past its line-count baseline (same reason `HomeStagePresentation`
/// exists).
struct HomeLandingHero: View {
  /// Drives the staggered entrance; flipped once when the page appears.
  let reveal: Bool
  /// Ambient rotation applied to the mark, in degrees.
  let logoAngle: Double

  var body: some View {
    VStack(spacing: OmiSpacing.md) {
      logo
        .homeLandingReveal(reveal, delay: 0.0)

      Text("Ask omi anything")
        .scaledFont(size: OmiType.subheading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)
        .homeLandingReveal(reveal, delay: 0.08)

      Text("Your personal AI assistant, ready when you are")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .homeLandingReveal(reveal, delay: 0.14)
    }
    .frame(maxWidth: .infinity)
  }

  private var logo: some View {
    Group {
      if let logoImage = Self.logoImage {
        Image(nsImage: logoImage)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "circle.hexagongrid.fill")
          .resizable()
          .scaledToFit()
          .foregroundColor(OmiColors.textPrimary)
      }
    }
    .frame(width: 44, height: 44)
    .rotationEffect(.degrees(logoAngle))
    .accessibilityHidden(true)
  }

  /// Loaded once: the hero re-renders on every rotation tick, and decoding the
  /// PNG per frame would be a needless cost on an always-animating view.
  private static let logoImage: NSImage? = {
    guard let url = Bundle.resourceBundle.url(forResource: "herologo", withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }()
}

/// Suggested prompts under the landing composer. Tapping one continues the
/// same conversation. Renders nothing when there are no suggestions.
struct HomeLandingChips: View {
  let reveal: Bool
  let prompts: [String]
  let onSelect: (String) -> Void

  @ViewBuilder var body: some View {
    if prompts.isEmpty {
      EmptyView()
    } else {
      HStack(spacing: OmiSpacing.sm) {
        ForEach(prompts, id: \.self) { prompt in
          Button {
            onSelect(prompt)
          } label: {
            Text(prompt)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundColor(OmiColors.textSecondary)
              .lineLimit(1)
              .padding(.horizontal, OmiSpacing.md)
              .padding(.vertical, OmiSpacing.sm)
              .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
              .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
              .contentShape(Capsule(style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .homeLandingReveal(reveal, delay: 0.20)
    }
  }
}

/// Reveals the conversation when the user scrolls on the landing — the
/// transcript conceptually lives "above" the hero.
///
/// This taps an app-global event stream, so ownership matters more than the
/// gesture. `start` and `stop` are both idempotent and two owners call `stop`
/// (the hero's `onDisappear` and the page's), because a monitor that outlives
/// the landing would fire on every scroll anywhere in the app. Cleanup is
/// explicit rather than in `deinit`: Swift 6 forbids touching the non-Sendable
/// monitor token from a nonisolated deinit. The predicate is re-evaluated per
/// event so a scroll can never reveal from another surface or from under a
/// modal.
@MainActor
final class LandingScrollRevealMonitor: ObservableObject {
  private var monitor: Any?

  /// Minimum vertical delta that counts as deliberate, so trackpad jitter and
  /// horizontal swipes don't dismiss the landing by accident.
  static let minimumScrollDelta: CGFloat = 4

  static func isDeliberateScroll(deltaY: CGFloat) -> Bool {
    abs(deltaY) > minimumScrollDelta
  }

  var isRunning: Bool { monitor != nil }

  /// Installs the monitor if it isn't already running. `shouldReveal` gates on
  /// current state; `onReveal` runs at most once per qualifying scroll.
  func start(shouldReveal: @escaping () -> Bool, onReveal: @escaping () -> Void) {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      if shouldReveal(), Self.isDeliberateScroll(deltaY: event.scrollingDeltaY) {
        onReveal()
      }
      return event
    }
  }

  func stop() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }
}
