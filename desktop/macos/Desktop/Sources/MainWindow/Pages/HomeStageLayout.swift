import OmiTheme
import SwiftUI

/// Where the Home composer sits for a given stage mode.
enum HomeComposerSlot: Equatable {
  /// Centred in the empty hub: under the greeting, over the suggestion rows.
  case centered
  /// Docked at the foot of the stage, floating over the transcript or the tray.
  case docked
}

/// The two placement decisions the merged Home stage makes, kept pure so both
/// can be exercised without booting a view.
enum HomeComposerPlacement {
  nonisolated static func slot(for mode: HomeStageMode) -> HomeComposerSlot {
    switch mode {
    case .hub: return .centered
    case .chat, .connect: return .docked
    }
  }

  /// Whether a mode change travels the composer or just places it.
  ///
  /// Home can switch straight to chat from inside its own `onAppear` — the
  /// onboarding opener and "Continue in Omi" both do — so the very first change
  /// lands on the first layout pass. Animating there slides the composer down
  /// from the hub's centre on every launch that restores a transcript, which is
  /// a launch artefact rather than a transition anyone performed.
  nonisolated static func shouldAnimate(
    from: HomeStageMode,
    to: HomeStageMode,
    isInitialAppearance: Bool
  ) -> Bool {
    if isInitialAppearance { return false }
    return from != to
  }
}

/// Home's stage: the mode surface underneath, one composer column on top.
///
/// The column's root is never conditional and the composer holds the same tuple
/// index in every mode, so hub → chat is a frame change inside a single view
/// identity — first responder survives, the bar's own hover and drop state
/// survive, and the travel is an ordinary animatable layout change with no
/// offset maths and no second measurement. Every branch therefore lives in the
/// composer's *siblings*: the moment an `if` wraps the composer itself the two
/// arms take distinct structural identities and the travel is a crossfade
/// again, which is the defect this layout exists to remove.
struct HomeStageLayout<
  ModeContent: View,
  Headline: View,
  Goals: View,
  Composer: View,
  Suggestions: View
>: View {
  let slot: HomeComposerSlot
  let headlineGap: CGFloat
  let suggestionsGap: CGFloat
  let modeContent: ModeContent
  let headline: Headline
  let goals: Goals
  let composer: Composer
  let suggestions: Suggestions

  init(
    slot: HomeComposerSlot,
    headlineGap: CGFloat,
    suggestionsGap: CGFloat,
    @ViewBuilder modeContent: () -> ModeContent,
    @ViewBuilder headline: () -> Headline,
    @ViewBuilder goals: () -> Goals,
    @ViewBuilder composer: () -> Composer,
    @ViewBuilder suggestions: () -> Suggestions
  ) {
    self.slot = slot
    self.headlineGap = headlineGap
    self.suggestionsGap = suggestionsGap
    self.modeContent = modeContent()
    self.headline = headline()
    self.goals = goals()
    self.composer = composer()
    self.suggestions = suggestions()
  }

  private var isCentered: Bool { slot == .centered }

  var body: some View {
    ZStack(alignment: .bottom) {
      modeContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      VStack(spacing: 0) {
        if isCentered {
          Spacer(minLength: 0)
          headline
            .padding(.bottom, headlineGap)
          goals
        }

        composer

        if isCentered {
          suggestions
            .padding(.top, suggestionsGap)
          Spacer(minLength: 0)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
  }
}
