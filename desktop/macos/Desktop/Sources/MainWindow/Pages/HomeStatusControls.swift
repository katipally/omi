import OmiTheme
import SwiftUI

/// The Capture and Listening status chips that sit in the Home header.
///
/// Split out of `DashboardPage` so the page stays under its line-count
/// baseline; these are self-contained presentation views driven entirely by
/// their inputs.

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
    .buttonStyle(.plain)
    .disabled(isToggling)
    .onHover { isHovering = $0 }
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
    return isHovering ? HomePalette.tile.opacity(0.6) : Color.clear
  }

  private var statusStroke: Color {
    if status.isActive {
      return HomePalette.green.opacity(0.38)
    }
    if status.isBlocked {
      return status.indicator.opacity(isHovering ? 0.54 : 0.38)
    }
    return HomePalette.hairline.opacity(isHovering ? 0.6 : 0.0)
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

  @State private var isHovering = false

  // Fixed-size chip that matches Capture exactly: icon + title, no hover-grow.
  // On/off/blocked is conveyed by color; the listening mode moves to a
  // right-click menu so the resting pill never changes size or reveals extras
  // — a header control that resizes under the pointer makes the whole bar
  // twitch as you move across it.
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
      .foregroundStyle(
        status.isActive ? HomePalette.ink : (status.isBlocked ? status.indicator : HomePalette.muted)
      )
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(height: 34)
      .background(Capsule(style: .continuous).fill(statusFill))
      .overlay(Capsule(style: .continuous).stroke(statusStroke, lineWidth: 1))
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isToggling)
    .onHover { isHovering = $0 }
    .omiAnimation(.easeInOut(duration: 0.14), value: isHovering)
    .help("Listening: \(status.text), \(modeTitle)")
    .accessibilityLabel("Listening \(status.text), \(modeTitle)")
    .contextMenu {
      Button(isMeetingsOnly ? "Listen always" : "Listen only during meetings", action: modeAction)
    }
    // The right-click menu is invisible to VoiceOver and Full Keyboard Access,
    // so the mode toggle stays reachable as a named action.
    .accessibilityAction(named: isMeetingsOnly ? "Listen always" : "Listen only during meetings") {
      modeAction()
    }
  }

  private var statusFill: Color {
    if status.isActive {
      return HomePalette.green.opacity(isHovering ? 0.20 : 0.12)
    }
    if status.isBlocked {
      return status.indicator.opacity(isHovering ? 0.16 : 0.10)
    }
    return isHovering ? HomePalette.tile.opacity(0.6) : Color.clear
  }

  private var statusStroke: Color {
    if status.isActive {
      return HomePalette.green.opacity(0.38)
    }
    if status.isBlocked {
      return status.indicator.opacity(isHovering ? 0.54 : 0.38)
    }
    return HomePalette.hairline.opacity(isHovering ? 0.6 : 0.0)
  }
}
