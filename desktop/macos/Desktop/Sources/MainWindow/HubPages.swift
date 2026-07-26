import OmiTheme
import SwiftUI

/// The two "hub" tabs — Memory (Memories / Conversations / Brain Map) and Focus
/// (Insights / Focus) — plus the section switcher they share.
///
/// Split out of `DesktopHomeView` to keep that file under the 1,500-line
/// ratchet threshold; these are self-contained page wrappers.

/// The section switcher shared by the hub tabs.
/// (Memory: Memories / Conversations / Brain Map. Focus: Insights / Focus.)
struct HubSegmentedControl: View {
  let segments: [String]
  @Binding var selection: Int

  var body: some View {
    OmiSegmentedControl(segments: segments, selection: $selection)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

struct MemoryHubPage: View {
  let appState: AppState
  let viewModelContainer: ViewModelContainer
  @AppStorage(MemoryHubDestination.storageKey) private var destinationRawValue =
    MemoryHubDestination.memories.rawValue
  /// The control drives this, not `@AppStorage` directly. An AppStorage write
  /// round-trips through UserDefaults and republishes on a later runloop turn,
  /// which lands outside the `withAnimation` transaction — the selected capsule
  /// jumps instead of sliding. Local state animates; the mirror below persists.
  @State private var selection = MemoryHubDestination.persisted.rawValue
  @ObservedObject private var conversationDetailState = ConversationDetailAutomationState.shared

  private var destination: MemoryHubDestination {
    MemoryHubDestination(rawValue: selection) ?? .memories
  }

  /// Memories follows the same readable-column policy as Conversations, and
  /// yields the cap for the same reason: a linked conversation's transcript
  /// drawer needs the width. Sharing `MemoryHubLayoutPolicy` is what keeps the
  /// two sections the same shape instead of one column being narrower than its
  /// neighbour for no reason the user can see.
  private var memoriesUsesAvailableWidth: Bool {
    MemoryHubLayoutPolicy.usesAvailableWidth(
      conversationID: viewModelContainer.memoriesViewModel.linkedConversation?.id,
      presentedConversationID: conversationDetailState.openConversationId,
      transcriptDrawerOpen: conversationDetailState.transcriptDrawerOpen
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      // Its own band, divided from the page below, so it reads as "which
      // section am I in" chrome rather than another control belonging to the
      // page's own header.
      OmiSegmentedControl(
        segments: MemoryHubDestination.allCases.map(\.title),
        selection: $selection
      )
      .padding(.vertical, OmiSpacing.md)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(OmiColors.border.opacity(0.25))
          .frame(height: 1)
      }

      Group {
        switch destination {
        case .memories:
          MemoriesPage(
            viewModel: viewModelContainer.memoriesViewModel,
            graphViewModel: viewModelContainer.memoryGraphViewModel
          )
          .frame(
            maxWidth: memoriesUsesAvailableWidth ? .infinity : MemoryHubLayoutPolicy.readableContentWidth,
            maxHeight: .infinity
          )
          .animation(OmiMotion.gated(.easeInOut(duration: 0.22)), value: memoriesUsesAvailableWidth)
        case .conversations:
          ConversationsPageHost(appState: appState)
        case .brainMap:
          // The map keeps its uncapped width so panning never hits an
          // artificial boundary; it just fills the area below the control.
          MemoryGraphPage(viewModel: viewModelContainer.memoryGraphViewModel)
        }
      }
      .id(destination)
      .transition(.opacity.animation(OmiMotion.gated(.easeInOut(duration: 0.2))))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: selection) { _, new in destinationRawValue = new }
    // External routing (Cmd+2, automation, the notification handlers in
    // DesktopHomeView) writes the stored key directly; mirror it back in.
    .onChange(of: destinationRawValue) { _, new in
      guard new != selection else { return }
      OmiMotion.withGated(OmiSegmentedMetrics.selectionAnimation) { selection = new }
    }
  }
}

/// "Focus" tab — Focus + Insights folded into one surface.
struct FocusHubPage: View {
  @State private var segment = 0

  var body: some View {
    VStack(spacing: 0) {
      HubSegmentedControl(segments: ["Insights", "Focus"], selection: $segment)
        .padding(.top, OmiSpacing.md)
        .padding(.horizontal, OmiSpacing.section)
        .padding(.bottom, OmiSpacing.sm)

      Group {
        if segment == 0 {
          InsightPage()
        } else {
          FocusPage()
        }
      }
      .id(segment)
      .transition(.opacity.animation(OmiMotion.gated(.easeInOut(duration: 0.2))))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
