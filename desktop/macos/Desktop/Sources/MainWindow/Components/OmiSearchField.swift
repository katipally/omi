import OmiTheme
import SwiftUI

/// One search interaction for the desktop's list surfaces.
///
/// Queries commit after a short pause while clearing commits immediately. The
/// coordinator keeps that timing and cancellation behavior identical across
/// Memories and Conversations without coupling either page to the other's data.
@MainActor
final class DebouncedSearchCoordinator: ObservableObject {
  typealias Sleeper = @Sendable (UInt64) async throws -> Void

  static let standardDelayNanoseconds: UInt64 = 250_000_000

  private let delayNanoseconds: UInt64
  private let sleeper: Sleeper
  private var pendingTask: Task<Void, Never>?

  init(
    delayNanoseconds: UInt64 = DebouncedSearchCoordinator.standardDelayNanoseconds,
    sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
  ) {
    self.delayNanoseconds = delayNanoseconds
    self.sleeper = sleeper
  }

  deinit {
    pendingTask?.cancel()
  }

  func submit(
    _ rawQuery: String,
    perform: @escaping @MainActor (String) async -> Void
  ) {
    pendingTask?.cancel()

    let query = Self.normalized(rawQuery)
    guard !query.isEmpty else {
      pendingTask = Task { await perform("") }
      return
    }

    let delayNanoseconds = delayNanoseconds
    let sleeper = sleeper
    pendingTask = Task {
      do {
        try await sleeper(delayNanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await perform(query)
    }
  }

  static func normalized(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func isActive(_ query: String) -> Bool {
    !normalized(query).isEmpty
  }
}

/// The one search field for the desktop app.
///
/// A capsule that brightens its fill and ring while focused, matching the chip
/// and segmented-control language so a header row of mixed controls reads as
/// one set. Focus is owned here rather than by each page: every call site wants
/// the same ring, and none of them had a second use for the state.
struct OmiSearchField: View {
  let placeholder: String
  @Binding var text: String
  var isLoading = false
  /// Overrides the spoken label when the placeholder reads poorly aloud
  /// (trailing ellipses, abbreviations).
  var accessibilityLabel: String? = nil

  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      Group {
        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "magnifyingglass")
            .scaledFont(size: OmiType.body, weight: .medium)
        }
      }
      .frame(width: 16, height: 16)
      .foregroundStyle(OmiColors.textTertiary)

      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .scaledFont(size: OmiType.body)
        .foregroundStyle(OmiColors.textPrimary)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel ?? placeholder)

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .scaledFont(size: OmiType.body)
            .foregroundStyle(OmiColors.textTertiary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, OmiSpacing.md)
    .frame(minHeight: OmiChrome.controlHeight)
    .background(
      Capsule(style: .continuous)
        .fill(Color.white.opacity(isFocused ? 0.10 : 0.06))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.white.opacity(isFocused ? 0.22 : 0.08), lineWidth: 1)
        )
    )
    .contentShape(Capsule(style: .continuous))
    .onTapGesture { isFocused = true }
    .omiAnimation(.easeOut(duration: 0.15), value: isFocused)
    .accessibilityElement(children: .contain)
  }
}
