import AppKit
import OmiTheme
import SwiftUI

// MARK: - Sheet Header

/// The band a modal sheet opens with: what the sheet is on the left, the way
/// out of it on the right, a divider under both.
///
/// `title` is not optional on purpose. A header that can render nothing is how
/// a sheet ends up spending a full row of chrome on a lone close glyph, which
/// reads as the card starting too low rather than as a header at all.
struct OmiSheetHeader<Leading: View, Trailing: View>: View {
  private let title: String
  private let subtitle: String?
  private let leading: Leading
  private let trailing: Trailing
  private let onClose: () -> Void

  init(
    title: String,
    subtitle: String? = nil,
    onClose: @escaping () -> Void,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.onClose = onClose
    self.leading = leading()
    self.trailing = trailing()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: OmiSpacing.md) {
        leading

        // The trait sits on the text block rather than the whole row so the
        // close and action buttons stay their own reachable elements.
        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
            .lineLimit(2)

          if let subtitle {
            Text(subtitle)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
              .lineLimit(1)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        Spacer(minLength: OmiSpacing.md)

        trailing

        DismissButton(action: onClose)
      }
      .frame(minHeight: OmiChrome.controlHeight)
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.lg)

      Divider()
        .background(OmiColors.border)
    }
  }
}

extension OmiSheetHeader where Leading == EmptyView, Trailing == EmptyView {
  init(title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
    self.init(
      title: title,
      subtitle: subtitle,
      onClose: onClose,
      leading: { EmptyView() },
      trailing: { EmptyView() }
    )
  }
}

extension OmiSheetHeader where Leading == EmptyView {
  init(
    title: String,
    subtitle: String? = nil,
    onClose: @escaping () -> Void,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.init(
      title: title,
      subtitle: subtitle,
      onClose: onClose,
      leading: { EmptyView() },
      trailing: trailing
    )
  }
}

extension OmiSheetHeader where Trailing == EmptyView {
  init(
    title: String,
    subtitle: String? = nil,
    onClose: @escaping () -> Void,
    @ViewBuilder leading: () -> Leading
  ) {
    self.init(
      title: title,
      subtitle: subtitle,
      onClose: onClose,
      leading: leading,
      trailing: { EmptyView() }
    )
  }
}

// MARK: - Safe Dismiss Button

/// Retired: `DismissButton` replaced it, because a real `Button` is what makes
/// the close control reachable by keyboard and nameable by accessibility.
/// Nothing constructs this any more; it stays in-tree so its removal can be its
/// own reviewable change.
///
/// A dismiss button that prevents click-through to underlying views on macOS.
/// Uses onTapGesture with async delay to ensure the click is fully consumed before dismissing.
/// The key is to wait for the full mouse event cycle to complete before triggering dismiss.
struct SafeDismissButton: View {
  let dismiss: DismissAction
  var icon: String = "xmark"
  var showBackground: Bool = true

  @State private var isPressed = false

  var body: some View {
    Image(systemName: icon)
      .scaledFont(size: OmiType.body, weight: .medium)
      .foregroundColor(isPressed ? OmiColors.textTertiary : OmiColors.textSecondary)
      .frame(width: 28, height: 28)
      .background(showBackground ? OmiColors.backgroundSecondary : Color.clear)
      .clipShape(Circle())
      .contentShape(Circle())
      .opacity(isPressed ? 0.7 : 1.0)
      .onTapGesture {
        guard !isPressed else { return }  // Prevent double-tap
        isPressed = true

        let mouseLocation = NSEvent.mouseLocation
        log("DISMISS: Tap gesture fired at mouse position: \(mouseLocation)")

        // Consume the click by resigning first responder
        NSApp.keyWindow?.makeFirstResponder(nil)

        // Post a mouse-up event to ensure any pending click is consumed
        if let window = NSApp.keyWindow {
          let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: window.mouseLocationOutsideOfEventStream,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
          )
          if let event = event {
            window.sendEvent(event)
            log("DISMISS: Sent synthetic mouse-up event")
          }
        }

        // Use async with longer delay to ensure mouse event fully completes
        Task { @MainActor in
          log("DISMISS: Starting 250ms delay before dismiss")
          // Longer delay to ensure mouse-up event is fully processed
          try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
          log("DISMISS: Delay complete, calling dismiss()")
          log("DISMISS: Mouse position before dismiss: \(NSEvent.mouseLocation)")
          dismiss()
          log("DISMISS: dismiss() called")
        }
      }
  }
}

// MARK: - Dismiss Button (Action-based)

/// A dismiss button that takes a closure instead of a DismissAction.
/// Used for overlay-based sheets where the dismiss is controlled externally.
/// A real Button (not a tap gesture) so accessibility exposes it as a labeled
/// "Close" control and keyboard users can reach it.
struct DismissButton: View {
  let action: () -> Void
  var icon: String = "xmark"
  var showBackground: Bool = true
  var accessibilityLabel: String = "Close"

  var body: some View {
    Button {
      log("DISMISS_BUTTON: Activated")

      // Commit any in-progress field editing before tearing the sheet down.
      NSApp.keyWindow?.makeFirstResponder(nil)

      OmiMotion.withGated(.easeOut(duration: 0.2)) {
        action()
      }
    } label: {
      Image(systemName: icon)
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)
        .frame(width: 28, height: 28)
        .background(showBackground ? OmiColors.backgroundSecondary : Color.clear)
        .clipShape(Circle())
        .contentShape(Circle())
    }
    .buttonStyle(DismissButtonPressStyle())
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct DismissButtonPressStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}
