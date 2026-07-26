import OmiTheme
import SwiftUI

/// The Capture and Listening status chips that sit in the Home header.
///
/// Split out of `DashboardPage` so the page stays under its line-count
/// baseline; these are self-contained presentation views driven entirely by
/// their inputs.

/// Press feedback for the header chips. `.plain` gives them none at all, so a
/// click reads as nothing happening until the underlying service catches up:
/// the chips toggle system-wide capture, which can take a beat.
private struct HomeChipPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .omiAnimation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct HomeStatusButton: View {
  let title: String
  let systemImage: String
  let status: HomeStatusState
  let isToggling: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        ZStack {
          if isToggling {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(0.55)
          } else {
            Image(systemName: systemImage)
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
        }
        .frame(width: 18, height: 18)

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .lineLimit(1)
      }
      .foregroundStyle(status.isActive ? HomePalette.ink : (status.isBlocked ? status.indicator : HomePalette.muted))
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(height: 34)
      .background(
        Capsule(style: .continuous)
          .fill(statusFill)
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(statusStroke, lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(HomeChipPressStyle())
    .disabled(isToggling)
    // A disabled chip still receives hover events; letting it light up would
    // promise a click it will not accept.
    .onHover { isHovering = $0 && !isToggling }
    .omiAnimation(.easeInOut(duration: 0.14), value: isHovering)
    .help("\(title): \(status.text)")
    .accessibilityLabel("\(title) \(status.text)")
  }

  private var statusFill: Color {
    if status.isActive {
      return HomePalette.green.opacity(isHovering ? 0.20 : 0.12)
    }
    if status.isBlocked {
      return status.indicator.opacity(isHovering ? 0.16 : 0.10)
    }
    return isHovering ? HomePalette.tile.opacity(0.6) : HomePalette.panel
  }

  private var statusStroke: Color {
    if status.isActive {
      return HomePalette.green.opacity(0.38)
    }
    if status.isBlocked {
      return status.indicator.opacity(isHovering ? 0.54 : 0.38)
    }
    // Off is a state, not an absence: the outline keeps the control on screen
    // so it can be found without sweeping the pointer across the header.
    return HomePalette.hairline.opacity(isHovering ? 0.85 : 0.58)
  }
}

/// The chip treatment for each listening state. Standby is neutral rather than
/// green, because the microphone is stopped, and brighter than off, because the
/// feature is armed and one call away from recording.
extension ListeningChipState {
  init(status: HomeStatusState) {
    if status.isBlocked {
      self = .blocked
    } else {
      self = status.isActive ? .capturing : .off
    }
  }

  fileprivate func fill(isHovering: Bool) -> Color {
    switch self {
    case .capturing:
      return HomePalette.green.opacity(isHovering ? 0.20 : 0.12)
    case .standby:
      return HomePalette.ink.opacity(isHovering ? 0.14 : 0.08)
    case .off:
      return isHovering ? HomePalette.tile.opacity(0.6) : HomePalette.panel
    case .blocked:
      return statusState.indicator.opacity(isHovering ? 0.16 : 0.10)
    }
  }

  fileprivate func stroke(isHovering: Bool) -> Color {
    switch self {
    case .capturing:
      return HomePalette.green.opacity(0.38)
    case .standby:
      return HomePalette.ink.opacity(isHovering ? 0.44 : 0.30)
    case .off:
      return HomePalette.hairline.opacity(isHovering ? 0.85 : 0.58)
    case .blocked:
      return statusState.indicator.opacity(isHovering ? 0.54 : 0.38)
    }
  }

  fileprivate var ink: Color {
    switch self {
    case .capturing:
      return HomePalette.ink
    case .standby:
      return HomePalette.secondary
    case .off:
      return HomePalette.muted
    case .blocked:
      return statusState.indicator
    }
  }
}

struct HomeListeningStatusButton: View {
  let title: String
  let systemImage: String
  let status: HomeStatusState
  let modeTitle: String
  let isMeetingsOnly: Bool
  let isToggling: Bool
  let action: () -> Void
  let modeAction: () -> Void
  /// Callers that can tell a live recording apart from a shut capture gate pass
  /// the richer state; the rest fall back to on/off/blocked.
  var chipState: ListeningChipState? = nil
  /// Printed after the title so the current mode is legible without hovering.
  var modeBadge: String? = nil
  /// Supplying both turns the right-click menu into a full three-mode picker.
  var modeOptions: [ListeningModeOption] = []
  var setMode: ((AssistantSettings.SystemAudioCaptureMode) -> Void)? = nil
  var cycleMode: (() -> Void)? = nil

  @State private var isHovering = false

  // Fixed-height chip that matches Capture exactly. The resting pill never
  // resizes under the pointer, since a header control that grows on hover makes
  // the whole bar twitch as you move across it. The mode picker is an overlay
  // the caller reveals below the chip, plus a right-click menu and a named
  // accessibility action for the paths that have no pointer.
  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        ZStack {
          if isToggling {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(0.55)
          } else {
            Image(systemName: systemImage)
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
        }
        .frame(width: 18, height: 18)

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .lineLimit(1)
          .fixedSize()

        if let modeBadge {
          Text(modeBadge)
            .scaledFont(size: OmiType.micro, weight: .semibold)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, OmiSpacing.xs)
            .frame(height: 16)
            .background(Capsule(style: .continuous).fill(HomePalette.ink.opacity(0.10)))
            .transition(.opacity)
        }
      }
      .foregroundStyle(chip.ink)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(height: 34)
      .background(Capsule(style: .continuous).fill(chip.fill(isHovering: isHovering)))
      .overlay(Capsule(style: .continuous).stroke(chip.stroke(isHovering: isHovering), lineWidth: 1))
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(HomeChipPressStyle())
    .disabled(isToggling)
    .onHover { isHovering = $0 && !isToggling }
    .omiAnimation(.easeInOut(duration: 0.14), value: isHovering)
    .omiAnimation(.easeInOut(duration: 0.18), value: chip)
    .omiAnimation(.easeInOut(duration: 0.18), value: modeBadge)
    .help("Listening: \(chip.statusText), \(modeTitle)")
    .accessibilityLabel("Listening \(chip.statusText), \(modeTitle)")
    .contextMenu {
      if let setMode, !modeOptions.isEmpty {
        ForEach(modeOptions) { option in
          Button {
            setMode(option.mode)
          } label: {
            // A checkmark is the only affordance a menu row has for "you are
            // already in this one".
            if option.isCurrent {
              Label(option.title, systemImage: "checkmark")
            } else {
              Text(option.title)
            }
          }
        }
      } else {
        Button(isMeetingsOnly ? "Listen always" : "Listen only during meetings", action: modeAction)
      }
    }
    // The right-click menu is invisible to VoiceOver and Full Keyboard Access,
    // so the mode change stays reachable as a named action.
    .accessibilityAction(named: modeActionName) {
      performModeAction()
    }
  }

  private var chip: ListeningChipState {
    chipState ?? ListeningChipState(status: status)
  }

  /// Cycling is what lets a pointer-free path reach the third mode; the two-way
  /// wording stays for callers that only have the two-way toggle.
  private var modeActionName: String {
    guard cycleMode != nil else {
      return isMeetingsOnly ? "Listen always" : "Listen only during meetings"
    }
    return "Change listening mode"
  }

  private func performModeAction() {
    guard let cycleMode else {
      modeAction()
      return
    }
    cycleMode()
  }
}
