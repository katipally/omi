import AppKit
import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

/// The Home ask bar and the controls that live inside its pill.
///
/// Split out of `DashboardPage` so that file stays under its line-count
/// baseline; this is a self-contained input surface driven entirely by its
/// bindings.

/// Fixed geometry for the ask bar's trailing action slot.
///
/// One height for every mode is the whole point. The row is a bottom-aligned
/// `HStack`, so whichever child is tallest sets the pill's height — and the
/// four action modes are four different views. A capsule that is taller than a
/// circle makes the bar grow the moment Connect appears and shrink the moment
/// the field takes focus, which reads as the bar twitching under the pointer.
/// Reserving the same box for all four makes the swap a crossfade instead of a
/// resize.
enum HomeAskBarMetrics {
  /// Matches the paperclip's height, so neither edge of the row can drive the
  /// pill taller than the other.
  static let accessoryHeight: CGFloat = 30
  /// The trailing inset plus the accessory: what the measured-width path has to
  /// reserve for chrome regardless of which mode is showing.
  static let accessoryReserve: CGFloat = 96
}

/// The persistent home ask bar: a pill-shaped chat input with attachments
/// (paperclip + drag-drop, same limits as the chat page), a send/stop action,
/// and the Connect toggle living inside the pill.
struct HomeAskBar: View {
  @Binding var text: String
  let isSending: Bool
  let isStopping: Bool
  let isConnectActive: Bool
  var focus: FocusState<Bool>.Binding
  @Binding var attachments: [ChatAttachment]
  let onAttachmentsAdded: ([URL]) -> Void
  let onAttachmentRemoved: (String) -> Void
  let onSend: () -> Void
  let onStop: () -> Void
  let onConnect: () -> Void
  let onActivate: () -> Void

  @State private var isHovering = false
  @State private var isDropTargeted = false

  private var hasText: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Requires text: ChatProvider.sendMessage drops empty-text sends, so
  /// presenting attachment-only as sendable would silently do nothing.
  /// Staged files ride along with the typed message instead.
  private var canSend: Bool {
    hasText
  }

  private var isFocused: Bool { focus.wrappedValue }

  private var shellStroke: Color {
    if isDropTargeted { return Color.white.opacity(0.42) }
    return Color.white.opacity(isFocused ? 0.22 : 0.08)
  }

  var body: some View {
    VStack(spacing: OmiSpacing.sm) {
      if !attachments.isEmpty {
        AttachmentPreviewRow(
          attachments: attachments,
          onRemove: onAttachmentRemoved
        )
        .padding(.top, OmiSpacing.sm)
        .padding(.horizontal, OmiSpacing.md)
      }

      HStack(alignment: .bottom, spacing: OmiSpacing.sm) {
        Button(action: pickFiles) {
          Image(systemName: "paperclip")
            .scaledFont(size: OmiType.subheading, weight: .medium)
            .foregroundStyle(isFocused ? HomePalette.secondary : HomePalette.muted)
            .frame(width: 24, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(attachments.count >= kMaxChatAttachments)
        .help("Attach files")

        // Auto-growing input: `axis: .vertical` + `lineLimit(1...6)` grow the pill
        // as text wraps (scrolls past six lines). Return submits, Shift+Return
        // newlines — via onKeyPress, since a vertical field would otherwise insert
        // a newline on Return and never fire onSubmit.
        TextField(
          "",
          text: $text,
          prompt: Text("Ask omi anything").foregroundColor(HomePalette.muted),
          axis: .vertical
        )
        .textFieldStyle(.plain)
        .scaledFont(size: OmiType.subheading)
        .foregroundStyle(HomePalette.ink)
        .lineLimit(1...6)
        .focused(focus)
        .padding(.vertical, 5)
        .onKeyPress(phases: .down) { press in
          guard press.key == .return else { return .ignored }
          // Shift+Return falls through to the field's newline handling.
          if press.modifiers.contains(.shift) { return .ignored }
          handleSubmit()
          return .handled
        }

        actionButton
      }
      .padding(.leading, OmiSpacing.lg)
      .padding(.trailing, OmiSpacing.sm)
      .padding(.vertical, 7)
      .frame(minHeight: 44)
    }
    // Same recipe as OmiSearchField and omiSegmentedTrack: a translucent white
    // wash under a crisp 1px ring that brightens on focus.
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.white.opacity(isFocused ? 0.10 : (isHovering ? 0.08 : 0.06)))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(shellStroke, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.38), radius: 10, y: 4)
    .contentShape(.rect(cornerRadius: 22))
    .onTapGesture {
      onActivate()
      focus.wrappedValue = true
    }
    .onHover { isHovering = $0 }
    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    // Keyed on the mode itself, not on the three inputs that derive it. Keying
    // on `isFocused` and `canSend` separately left `isSending` uncovered, so
    // Connect -> Stop (which is what a suggestion tap does from an unfocused
    // bar) was the one transition that snapped.
    .omiAnimation(.easeOut(duration: 0.16), value: actionMode)
    .omiAnimation(.easeOut(duration: 0.16), value: isFocused)
    .omiAnimation(.easeOut(duration: 0.16), value: attachments.count)
  }

  private func pickFiles() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [
      .image, .jpeg, .png, .gif, .heic, .heif, .webP, .tiff, .bmp,
      .pdf, .plainText, .json, .commaSeparatedText, .html,
      .text, .content,
    ]
    if panel.runModal() == .OK {
      let remaining = max(0, kMaxChatAttachments - attachments.count)
      let urls = Array(panel.urls.prefix(remaining))
      if !urls.isEmpty {
        onAttachmentsAdded(urls)
      }
    }
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    ChatAttachmentDropHandler.collectURLs(from: providers) { [attachments] urls in
      guard !urls.isEmpty else { return }
      let remaining = max(0, kMaxChatAttachments - attachments.count)
      let allowed = Array(urls.prefix(remaining))
      if !allowed.isEmpty {
        onAttachmentsAdded(allowed)
      }
    }
  }

  private func handleSubmit() {
    if isSending {
      onStop()
    } else if canSend {
      onSend()
    }
  }

  /// Every mode occupies the same height, including the empty one. `.none`
  /// renders a zero-width `Color.clear` rather than `EmptyView` on purpose:
  /// `EmptyView` contributes no height at all, so focusing an empty field
  /// would drop the row's tallest child and collapse the pill.
  @ViewBuilder
  private var actionButton: some View {
    Group {
      switch actionMode {
      case .stop:
        stopButton
      case .send:
        sendButton
      case .connect:
        connectButton
      case .none:
        Color.clear.frame(width: 0)
      }
    }
    .frame(height: HomeAskBarMetrics.accessoryHeight)
  }

  /// Which control the trailing slot shows. A pure precedence rule, kept
  /// `nonisolated` so it can be exercised without a view or an actor hop.
  nonisolated static func actionMode(isSending: Bool, canSend: Bool, isFocused: Bool)
    -> HomeAskBarActionMode
  {
    if isSending { return .stop }
    if canSend { return .send }
    if isFocused { return .none }
    return .connect
  }

  private var actionMode: HomeAskBarActionMode {
    Self.actionMode(isSending: isSending, canSend: canSend, isFocused: isFocused)
  }

  private var sendButton: some View {
    Button(action: handleSubmit) {
      ZStack {
        Circle()
          .fill(Color.white)

        Image(systemName: "arrow.up")
          .scaledFont(size: OmiType.body, weight: .bold)
          .foregroundStyle(Color.black)
      }
      .frame(width: HomeAskBarMetrics.accessoryHeight, height: HomeAskBarMetrics.accessoryHeight)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Send")
    .accessibilityLabel("Send message")
  }

  private var stopButton: some View {
    Button(action: onStop) {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.14))

        if isStopping {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.6)
        } else {
          Image(systemName: "square.fill")
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundStyle(HomePalette.ink)
        }
      }
      .frame(width: HomeAskBarMetrics.accessoryHeight, height: HomeAskBarMetrics.accessoryHeight)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isStopping)
    .help("Stop")
    .accessibilityLabel("Stop response")
  }

  private var connectButton: some View {
    HomeAskBarConnectButton(isActive: isConnectActive, action: onConnect)
  }
}

enum HomeAskBarActionMode: Equatable {
  case connect
  case send
  case stop
  case none
}

struct HomeAskBarConnectButton: View {
  let isActive: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: "link")
          .scaledFont(size: OmiType.caption, weight: .semibold)

        Text("Connect")
          .scaledFont(size: OmiType.caption, weight: .semibold)
      }
      .foregroundStyle(isActive ? Color.black : HomePalette.ink)
      .padding(.horizontal, OmiSpacing.md)
      .frame(height: HomeAskBarMetrics.accessoryHeight)
      .background(
        Capsule(style: .continuous)
          .fill(isActive ? Color.white : Color.white.opacity(isHovering ? 0.14 : 0.07))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(isActive ? Color.clear : HomePalette.hairline, lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help("Connect data & use omi anywhere")
    .accessibilityLabel(isActive ? "Close connect" : "Connect")
  }
}
