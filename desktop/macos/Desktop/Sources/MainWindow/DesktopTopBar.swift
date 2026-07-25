import AppKit
import OmiTheme
import SwiftUI

/// The constant floating top bar that replaces the left nav rail: primary
/// navigation (Home / Memory / Tasks / Apps), a "new since you were last here"
/// counter (conversations · memories · tasks created while Omi wasn't in front),
/// and the Capture/Listening controls on the right.
struct DesktopTopBar: View {
  @Binding var selectedIndex: Int
  @ObservedObject var appState: AppState
  @ObservedObject var memoriesViewModel: MemoriesViewModel
  @ObservedObject var tasksStore: TasksStore
  /// Items created after this instant count as "new" — updated whenever Omi
  /// last resigned front (see DesktopHomeView).
  let sinceDate: Date
  /// Leading inset that clears the window traffic lights when the bar rides in
  /// the hidden-titlebar band with no sidebar to its left.
  var leadingInset: CGFloat = 0
  /// While settings are open the matching "Back to app" control lives on the
  /// sidebar glass, so this bar drops its own Settings chip.
  var isInSettings: Bool = false
  let onRewind: () -> Void
  /// Toggles the settings sidebar open/closed. Owned by DesktopHomeView so the
  /// back-navigation target (previous tab) stays correct.
  var onToggleSettings: () -> Void = {}

  @AppStorage(MemoryHubDestination.storageKey) private var memoryDestinationRawValue =
    MemoryHubDestination.memories.rawValue

  /// Drives the sliding selection inside the segmented nav track.
  @Namespace private var navSegmentNamespace

  private static let logoImage: NSImage? = {
    guard let url = Bundle.resourceBundle.url(forResource: "herologo", withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }()

  private struct NavItem: Identifiable {
    let index: Int
    let title: String
    let icon: String
    var id: Int { index }
  }

  private var navItems: [NavItem] {
    [
      NavItem(index: SidebarNavItem.dashboard.rawValue, title: "Home", icon: "house.fill"),
      NavItem(index: SidebarNavItem.conversations.rawValue, title: "Memory", icon: "brain"),
      NavItem(index: SidebarNavItem.tasks.rawValue, title: "Tasks", icon: "checklist"),
      NavItem(index: SidebarNavItem.apps.rawValue, title: "Apps", icon: "puzzlepiece.fill"),
    ]
  }

  private var newConversations: Int {
    appState.conversations.filter { $0.createdAt > sinceDate && $0.deleted != true }.count
  }
  private var newMemories: Int {
    memoriesViewModel.memories.filter { $0.createdAt > sinceDate }.count
  }
  private var newTasks: Int {
    tasksStore.tasks.filter { $0.createdAt > sinceDate && $0.deleted != true }.count
  }

  var body: some View {
    VStack(spacing: OmiSpacing.xs) {
      // Row 1 — toolbar aligned with the traffic lights: the Settings chip sits
      // by them (only while closed — in settings "Back to app" lives on the
      // sidebar glass), the Omi identity is centered, capture on the right.
      ZStack {
        omiIdentity

        HStack(spacing: OmiSpacing.md) {
          if !isInSettings {
            settingsChip
              .padding(.leading, leadingInset)
              .transition(.opacity)
          }
          Spacer(minLength: OmiSpacing.md)
          CaptureListeningControls(appState: appState, onRewind: onRewind)
        }
      }
      .frame(height: 34)

      // Row 2 — the segmented primary nav, centered below the identity.
      navSegments
    }
    .padding(.horizontal, OmiSpacing.lg)
    .padding(.top, 10)
    .padding(.bottom, OmiSpacing.sm)
    .background(WindowDragArea())
  }

  /// The app identity in the hidden-titlebar band: mark + wordmark, centered.
  private var omiIdentity: some View {
    HStack(spacing: OmiSpacing.xs) {
      if let logo = Self.logoImage {
        Image(nsImage: logo)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
      }
      Text("Omi")
        .scaledFont(size: OmiType.subheading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Opens settings. It sits by the traffic lights; when settings is open the
  /// matching "Back to app" control lives on the sidebar glass instead.
  private var settingsChip: some View {
    OmiChip(icon: "gearshape", title: "Settings", action: onToggleSettings)
  }

  /// One track holding the four primary tabs, so the selected fill slides
  /// between them instead of blinking on and off separate pills. Memory keeps
  /// its destination menu — it is a segment that also discloses.
  private var navSegments: some View {
    HStack(spacing: OmiSpacing.hairline) {
      ForEach(navItems) { item in
        if item.index == SidebarNavItem.conversations.rawValue {
          Menu {
            ForEach(MemoryHubDestination.allCases) { destination in
              Button {
                memoryDestinationRawValue = destination.rawValue
                OmiMotion.withGated(OmiSegmentedMetrics.selectionAnimation) {
                  selectedIndex = SidebarNavItem.conversations.rawValue
                }
              } label: {
                Label(destination.title, systemImage: destination.icon)
              }
            }
          } label: {
            navLabel(for: item, showsDisclosure: true)
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .help("Choose a Memory view")
        } else {
          Button {
            OmiMotion.withGated(OmiSegmentedMetrics.selectionAnimation) {
              selectedIndex = item.index
            }
          } label: {
            navLabel(for: item)
          }
          .buttonStyle(.plain)
          .help(item.title)
        }
      }
    }
    .omiSegmentedTrack()
  }

  private func navLabel(for item: NavItem, showsDisclosure: Bool = false) -> some View {
    HStack(spacing: OmiSpacing.xs) {
      Image(systemName: item.icon)
        .scaledFont(size: OmiType.caption, weight: .semibold)
      Text(item.title)
        .scaledFont(size: OmiType.caption, weight: .semibold)
      if showsDisclosure {
        Image(systemName: "chevron.down")
          .scaledFont(size: 8, weight: .bold)
          .foregroundStyle(OmiColors.textQuaternary)
      }
      // New-item badge lives on the segment it belongs to (Memory =
      // memories + conversations, Tasks = tasks) since Omi was last front.
      if newCount(for: item) > 0 {
        Text("+\(newCount(for: item))")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(OmiColors.textPrimary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Capsule(style: .continuous).fill(OmiColors.textPrimary.opacity(0.18)))
      }
    }
    .foregroundColor(selectedIndex == item.index ? OmiColors.textPrimary : OmiColors.textTertiary)
    .omiSegmentContent()
    .omiSegmentFill(
      isSelected: selectedIndex == item.index,
      namespace: navSegmentNamespace,
      geometryID: "navSegment"
    )
  }

  /// New-item count to badge on a nav button (since Omi was last in front).
  /// The Memory hub holds both memories and conversations, so its badge sums
  /// them; Tasks badges new tasks. Home/Apps have no counter.
  private func newCount(for item: NavItem) -> Int {
    switch item.index {
    case SidebarNavItem.conversations.rawValue: return newMemories + newConversations
    case SidebarNavItem.tasks.rawValue: return newTasks
    default: return 0
    }
  }
}

/// Lets the user drag the window by the top bar's empty areas, the way a native
/// toolbar behaves. Controls on top keep their own clicks; only the gaps drag.
private struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
  }
}
