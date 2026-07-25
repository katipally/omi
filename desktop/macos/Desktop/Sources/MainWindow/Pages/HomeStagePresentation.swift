import OmiTheme
import SwiftUI

enum HomeStageMode: Equatable {
  case hub
  case chat
  case connect
  /// The on-open landing: a centered hero (rotating mark + composer) shown
  /// before the transcript. Same conversation underneath — the first send
  /// transitions to `.chat` and continues the one shared thread.
  case landing

  /// Whether the user-facing collapse catchers (click-outside + Esc) mount.
  /// Only a panel that can collapse to a *different* resting surface gets a
  /// catcher. `hub` and `landing` are base surfaces, never overlays: mounting
  /// a catcher over them would invert the gesture and make a stray click or
  /// Esc *open* the chat.
  static func collapseCatcherActive(mode: HomeStageMode, resting: HomeStageMode) -> Bool {
    mode != resting && mode != .hub && mode != .landing
  }

  var automationLabel: String {
    switch self {
    case .hub: return "hub"
    case .chat: return "chat"
    case .connect: return "connect"
    case .landing: return "landing"
    }
  }
}

enum HomeHistoryPresentationPolicy {
  static func restingMode(isLoading: Bool, messageCount: Int) -> HomeStageMode {
    !isLoading && messageCount > 0 ? .chat : .hub
  }
}

/// Shared stage motion for Home panels, including the initial history restore
/// where the useful hub leaves upward and the completed chat rises from below.
private struct HomeStageDropModifier: ViewModifier {
  let offsetY: CGFloat
  let scale: CGFloat
  let opacity: Double

  func body(content: Content) -> some View {
    content
      .offset(y: offsetY)
      .scaleEffect(scale, anchor: .top)
      .opacity(opacity)
  }
}

extension AnyTransition {
  static var homeDropFromTop: AnyTransition {
    .modifier(
      active: HomeStageDropModifier(offsetY: -46, scale: 0.97, opacity: 0),
      identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
    )
  }

  static var homeHubFade: AnyTransition {
    .modifier(
      active: HomeStageDropModifier(offsetY: 14, scale: 1, opacity: 0),
      identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
    )
  }

  static var homeHubStage: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: HomeStageDropModifier(offsetY: 14, scale: 1, opacity: 0),
        identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
      ),
      removal: .modifier(
        active: HomeStageDropModifier(offsetY: -54, scale: 0.98, opacity: 0),
        identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
      )
    )
  }

  static var homeChatRise: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: HomeStageDropModifier(offsetY: 54, scale: 0.98, opacity: 0),
        identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
      ),
      removal: .modifier(
        active: HomeStageDropModifier(offsetY: -28, scale: 0.98, opacity: 0),
        identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
      )
    )
  }

  static var homeSuggestionsFade: AnyTransition {
    .modifier(
      active: HomeStageDropModifier(offsetY: 10, scale: 1, opacity: 0),
      identity: HomeStageDropModifier(offsetY: 0, scale: 1, opacity: 1)
    )
  }
}

extension View {
  /// Staggered fade + slight upward drift for a landing-hero element. The
  /// caller varies `delay` per element so they settle in sequence. Gates off
  /// under Reduce Motion.
  func homeLandingReveal(_ shown: Bool, delay: Double) -> some View {
    self
      .opacity(shown ? 1 : 0)
      .offset(y: shown ? 0 : 10)
      .animation(OmiMotion.gated(.easeOut(duration: 0.45).delay(delay)), value: shown)
  }
}
