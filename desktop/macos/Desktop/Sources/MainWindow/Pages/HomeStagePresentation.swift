import OmiTheme
import SwiftUI

enum HomeStageMode: Equatable {
  case hub
  case chat
  case connect

  /// Whether the user-facing collapse catchers (click-outside + Esc) mount.
  /// Only a surface that sits *over* the hub gets one. The hub is the base
  /// surface and never an overlay: a catcher over it would invert the gesture
  /// and make a stray click or Esc open the chat.
  static func collapseCatcherActive(mode: HomeStageMode, resting: HomeStageMode) -> Bool {
    mode != resting && mode != .hub
  }

  func topPadding(hub: CGFloat) -> CGFloat {
    switch self {
    case .hub: return hub
    case .chat: return 0
    case .connect: return OmiSpacing.lg
    }
  }

  var automationLabel: String {
    switch self {
    case .hub: return "hub"
    case .chat: return "chat"
    case .connect: return "connect"
    }
  }
}

enum HomeHistoryPresentationPolicy {
  /// The surface Home rests on, and the one every panel collapses back to.
  ///
  /// The hub is the front door unconditionally: it is where the day's brief and
  /// the actionable rows live, and a surface that only some launches show is a
  /// surface nobody designs for. History is one scroll or one send away, never
  /// auto-revealed.
  static let restingMode: HomeStageMode = .hub

  /// The stage Home opens on. Same answer every time — there is no session
  /// state to remember and therefore no way for two surfaces to disagree about
  /// which one is the front door.
  static let openingMode: HomeStageMode = .hub
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
  /// Staggered fade + slight upward drift for a hub element. The caller varies
  /// `delay` per element so they settle in sequence. Gates off under Reduce
  /// Motion.
  package func homeHubReveal(_ shown: Bool, delay: Double) -> some View {
    self
      .opacity(shown ? 1 : 0)
      .offset(y: shown ? 0 : 10)
      .animation(OmiMotion.gated(.easeOut(duration: 0.45).delay(delay)), value: shown)
  }
}
