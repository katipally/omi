import OmiTheme
import SwiftUI

// MARK: - Install Decision

/// The install-state decisions the marketplace surfaces share, kept as pure
/// functions so "installed" and "not installed" can be proven to resolve to
/// different treatments without rendering anything.
enum AppInstallDecision {

  /// What the card's primary control is offering right now. The provider keeps
  /// one loading flag per app id, so the enabled state at the moment the
  /// request started is what names the work in flight.
  enum Control: Equatable {
    case install
    case open
    case installing
    case removing
  }

  static func control(isEnabled: Bool, isLoading: Bool) -> Control {
    if isLoading { return isEnabled ? .removing : .installing }
    return isEnabled ? .open : .install
  }

  /// How a control state renders. Installed reads as a ghost button on the card
  /// surface, not-installed as the filled white call to action, the same split
  /// `ImportConnectorActionButton` uses, so the marketplace and the connector
  /// rows agree on what "you already have this" looks like.
  struct Treatment: Equatable {
    let title: String
    let isFilled: Bool
    let minWidth: CGFloat
    let showsProgress: Bool
  }

  static func treatment(for control: Control) -> Treatment {
    switch control {
    case .install:
      return Treatment(title: "Install", isFilled: true, minWidth: 72, showsProgress: false)
    case .open:
      return Treatment(title: "Open", isFilled: false, minWidth: 84, showsProgress: false)
    case .installing:
      return Treatment(title: "Installing", isFilled: true, minWidth: 96, showsProgress: true)
    case .removing:
      return Treatment(title: "Removing", isFilled: false, minWidth: 96, showsProgress: true)
    }
  }

  /// The live enabled state for an app id. Search populates `filteredApps`, so
  /// an app opened from a search result can be absent from the loaded catalog;
  /// falling straight through to the value captured when the sheet opened would
  /// strand its button on "Install" and let the install path push an
  /// already-enabled app back into setup.
  static func resolvedEnabled(
    appId: String,
    capturedEnabled: Bool,
    installedApps: [OmiApp],
    filteredApps: [OmiApp]?
  ) -> Bool {
    if let catalogApp = installedApps.first(where: { $0.id == appId }) { return catalogApp.enabled }
    if let searchResult = filteredApps?.first(where: { $0.id == appId }) { return searchResult.enabled }
    return capturedEnabled
  }
}

// MARK: - App Card (Full)

struct AppCard: View {
  let app: OmiApp
  let appProvider: AppProvider
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.md) {
          // App icon
          AsyncImage(url: URL(string: app.image)) { phase in
            switch phase {
            case .success(let image):
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            default:
              appIconPlaceholder
            }
          }
          .frame(width: 50, height: 50)
          .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius))
          .overlay(alignment: .bottomTrailing) {
            if app.enabled {
              installedBadge
            }
          }
          .omiAnimation(SBMotion.standard, value: app.enabled)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text(app.name)
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)
              .lineLimit(1)

            Text(app.author)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
              .lineLimit(1)
          }

          Spacer()
        }

        Text(app.description)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        HStack {
          // Rating and installs
          HStack(spacing: OmiSpacing.xs) {
            if let rating = app.formattedRating {
              HStack(spacing: OmiSpacing.hairline) {
                Image(systemName: "star.fill")
                  .scaledFont(size: OmiType.micro)
                  .foregroundColor(.yellow)
                Text(rating)
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(OmiColors.textTertiary)
              }
            }
            if let installs = app.formattedInstalls {
              HStack(spacing: OmiSpacing.hairline) {
                Image(systemName: "arrow.down.circle")
                  .scaledFont(size: OmiType.micro)
                  .foregroundColor(OmiColors.textTertiary)
                Text(installs)
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(OmiColors.textTertiary)
              }
            }
          }

          Spacer()

          // Get/Open button
          AppActionButton(app: app, appProvider: appProvider, onOpen: onSelect)
        }
      }
      .padding(OmiSpacing.md)
      .background(isHovering ? OmiColors.backgroundTertiary : OmiColors.backgroundSecondary)
      .cornerRadius(OmiChrome.smallControlRadius)
      // Second scan cue for an installed app: at grid density the badge alone
      // is easy to miss, and the outline survives a glance at the whole page.
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
          .stroke(app.enabled ? OmiColors.border : Color.clear, lineWidth: 1)
      )
      .omiAnimation(SBMotion.standard, value: app.enabled)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      OmiMotion.withGated(.easeOut(duration: 0.12)) { isHovering = hovering }
    }
  }

  /// Reads as "you have this" before any label is read, and carries the word
  /// "Installed" into the card's merged accessibility label so the cue is not
  /// purely visual.
  private var installedBadge: some View {
    Image(systemName: "checkmark.circle.fill")
      .symbolRenderingMode(.palette)
      .foregroundStyle(Color.black, Color.white)
      .scaledFont(size: OmiType.caption, weight: .semibold)
      .padding(OmiSpacing.hairline)
      .background(Circle().fill(OmiColors.backgroundPrimary))
      .offset(x: OmiSpacing.xxs, y: OmiSpacing.xxs)
      .transition(.scale.combined(with: .opacity))
      .accessibilityLabel("Installed")
  }

  private var appIconPlaceholder: some View {
    RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
      .fill(OmiColors.backgroundTertiary)
      .overlay(
        Image(systemName: "app.fill")
          .foregroundColor(OmiColors.textTertiary)
      )
  }
}

// MARK: - App Action Button

struct AppActionButton: View {
  let app: OmiApp
  let appProvider: AppProvider
  var onOpen: (() -> Void)? = nil

  @State private var isHovering = false

  private var control: AppInstallDecision.Control {
    AppInstallDecision.control(
      isEnabled: app.enabled,
      isLoading: appProvider.isAppLoading(app.id)
    )
  }

  var body: some View {
    let treatment = AppInstallDecision.treatment(for: control)

    Button(action: {
      if app.enabled {
        // If already enabled, open the app detail
        onOpen?()
      } else {
        // If not enabled, enable it
        Task { await appProvider.toggleApp(app) }
      }
    }) {
      HStack(spacing: OmiSpacing.xxs) {
        if treatment.showsProgress {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.55)
            .frame(width: 12, height: 12)
            .tint(treatment.isFilled ? .black : OmiColors.textSecondary)
        }

        Text(treatment.title)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .lineLimit(1)
      }
      .foregroundColor(treatment.isFilled ? .black : OmiColors.textPrimary)
      .padding(.horizontal, OmiSpacing.sm)
      // A minimum, not a fixed width: "Installing" at large Dynamic Type sizes
      // needs more room than "Open" ever will.
      .frame(minWidth: treatment.minWidth, minHeight: 28)
      .background(fill(for: treatment))
      .cornerRadius(OmiChrome.chipRadius)
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius)
          .stroke(OmiColors.border, lineWidth: 1)
      )
    }
    .buttonStyle(AppActionButtonPressStyle())
    .disabled(treatment.showsProgress)
    .onHover { hovering in
      OmiMotion.withGated(.easeOut(duration: 0.12)) { isHovering = hovering }
    }
    .omiAnimation(SBMotion.standard, value: control)
    .accessibilityLabel("\(treatment.title) \(app.name)")
  }

  /// Hover is suppressed while a request is in flight: the control is disabled
  /// then, and a surface that still lights up under the cursor promises a tap
  /// it will not accept.
  private func fill(for treatment: AppInstallDecision.Treatment) -> Color {
    let isHighlighted = isHovering && !treatment.showsProgress
    if treatment.isFilled {
      return isHighlighted ? Color.white.opacity(0.86) : Color.white
    }
    // The card behind this button changes surface on its own hover, so the ghost
    // lift is a translucent overlay instead of a second surface token that could
    // land on the same color the card just moved to.
    return isHighlighted ? Color.white.opacity(0.12) : OmiColors.backgroundTertiary
  }
}

/// Pressed feedback for the card's install control. The card underneath is
/// itself a button, so the control needs its own press signal to show which of
/// the two the click landed on.
private struct AppActionButtonPressStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.75 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .omiAnimation(SBMotion.toggle, value: configuration.isPressed)
  }
}

// MARK: - App Install Error Banner

/// The rendering path for `AppProvider.errorMessage`. A failed install
/// otherwise stops its spinner and leaves the button reading "Install", which
/// is indistinguishable from never having tapped it.
struct AppInstallErrorBanner: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)
        .accessibilityHidden(true)

      Text(message)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textPrimary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: OmiSpacing.xs)

      DismissButton(
        action: onDismiss,
        showBackground: false,
        accessibilityLabel: "Dismiss error"
      )
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
        .fill(OmiColors.backgroundSecondary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
        .stroke(OmiColors.border, lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
  }
}
