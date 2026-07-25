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

  private var destination: MemoryHubDestination {
    MemoryHubDestination(rawValue: destinationRawValue) ?? .memories
  }

  var body: some View {
    // The top-bar menu can jump straight here from any tab, but once you are on
    // Memory nothing in the menu's label says which of the three destinations
    // you landed on. This control is the visible current-state indicator, and
    // switching sections without going back up to the menu.
    VStack(spacing: 0) {
      // Its own band, divided from the page below, so it reads as "which
      // section am I in" chrome rather than another control belonging to the
      // page's own header.
      OmiSegmentedControl(
        segments: MemoryHubDestination.allCases.map(\.title),
        selection: Binding(
          get: { destination.rawValue },
          set: { destinationRawValue = $0 }
        )
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
        case .conversations:
          ConversationsPageHost(appState: appState)
        case .brainMap:
          // The map keeps its uncapped width so panning never hits an
          // artificial boundary; it just fills the area below the control.
          MemoryGraphPage(viewModel: viewModelContainer.memoryGraphViewModel)
        }
      }
      .id(destination)
      .transition(.opacity.animation(.easeInOut(duration: 0.2)))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      .transition(.opacity.animation(.easeInOut(duration: 0.2)))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
