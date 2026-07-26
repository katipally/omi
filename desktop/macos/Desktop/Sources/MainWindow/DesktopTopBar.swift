import AppKit
import OmiTheme
import SwiftUI

/// The constant floating top bar that replaces the left nav rail: primary
/// navigation (Home / Memory / Tasks / Apps), a "new since you were last here"
/// counter (conversations · memories · tasks created while Omi wasn't in front),
/// and the Capture/Listening controls on the right.
struct DesktopTopBar: View {
  @Binding var selectedIndex: Int
  @Binding var memoryDestinationRawValue: Int
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

  /// Drives the identity mark. Optional because the view exporter renders this
  /// bar from stub stores and has no live chat to observe.
  var chatProvider: ChatProvider? = nil
  /// Drives the sliding selection inside the segmented nav track.
  @Namespace private var navSegmentNamespace
  /// The segment under the pointer, so the nav track gets the same hover wash
  /// as every other segmented surface.
  @State private var hoveredIndex: Int?

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
  /// The mark is the live one, so the window title moves with the same motion
  /// the transcript's mark is making rather than sitting frozen beside it.
  private var omiIdentity: some View {
    HStack(spacing: OmiSpacing.xs) {
      if let chatProvider {
        OmiIdentityMark(chatProvider: chatProvider)
      } else if let logo = Self.logoImage {
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
  /// between them instead of blinking on and off separate pills. Memory has no
  /// destination menu: the hub's own segmented control below is the single
  /// switcher, so this stays four plain, one-click segments.
  private var navSegments: some View {
    HStack(spacing: OmiSpacing.hairline) {
      ForEach(navItems) { item in
        Button {
          OmiMotion.withGated(OmiSegmentedMetrics.selectionAnimation) {
            selectedIndex = item.index
          }
        } label: {
          navLabel(for: item)
        }
        .buttonStyle(.plain)
        .help(helpTitle(for: item))
        .accessibilityIdentifier(navIdentifier(for: item))
        .onHover { hovering in
          OmiMotion.withGated(OmiSegmentedMetrics.hoverAnimation) {
            hoveredIndex = hovering ? item.index : (hoveredIndex == item.index ? nil : hoveredIndex)
          }
        }
      }
    }
    .omiSegmentedTrack()
  }

  /// The Memory hub's current section, owned by the shell. The bar reads it but
  /// never switches it: the hub's own segmented control is the single switcher.
  private var memoryDestination: MemoryHubDestination {
    MemoryHubDestination(rawValue: memoryDestinationRawValue) ?? .memories
  }

  /// Memory names the section it lands on, so the segment still discloses where
  /// the click goes without offering a second destination switcher.
  private func helpTitle(for item: NavItem) -> String {
    guard item.index == SidebarNavItem.conversations.rawValue else { return item.title }
    return "\(item.title): \(memoryDestination.title)"
  }

  /// Stable automation handles for the nav. Memory keeps the identifier the
  /// dropdown-era pill used so automation targeting it still finds the segment.
  private func navIdentifier(for item: NavItem) -> String {
    item.index == SidebarNavItem.conversations.rawValue
      ? "memory-navigation-button" : "\(item.title.lowercased())-navigation-button"
  }

  private func navLabel(for item: NavItem) -> some View {
    HStack(spacing: OmiSpacing.xs) {
      Image(systemName: item.icon)
        .scaledFont(size: OmiType.caption, weight: .semibold)
      Text(item.title)
        .scaledFont(size: OmiType.caption, weight: .semibold)
      // New-item badge lives on the segment it belongs to (Memory =
      // memories + conversations, Tasks = tasks) since Omi was last front.
      if newCount(for: item) > 0 {
        Text("+\(newCount(for: item))")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(OmiColors.textPrimary)
          .padding(.horizontal, OmiSpacing.xxs)
          .padding(.vertical, 1)
          .background(Capsule(style: .continuous).fill(OmiColors.textPrimary.opacity(0.18)))
      }
    }
    .foregroundColor(selectedIndex == item.index ? OmiColors.textPrimary : OmiColors.textTertiary)
    .omiSegmentContent()
    .omiSegmentFill(
      isSelected: selectedIndex == item.index,
      isHovering: hoveredIndex == item.index,
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

/// The window identity's mark, driven by the same chat state the transcript's
/// mark reads, so the two are one object moving together.
///
/// It owns the observation rather than the bar doing so: a streaming reply
/// republishes on every token batch, and the nav, badges, and capture controls
/// have no reason to re-render for that.
private struct OmiIdentityMark: View {
  @ObservedObject var chatProvider: ChatProvider

  var body: some View {
    ChatOmiMark(
      motion: chatProvider.isSending
        ? ChatWorkingStatus.motion(for: chatProvider.messages.last) : nil,
      size: 18,
      anchor: .centered
    )
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

// MARK: - Retired pill navigation

/// The pill-per-tab top navigation, and the hover dropdown that used to hang off
/// the Memory pill. Nothing constructs these since the nav became one segmented
/// track and the Memory hub's own switcher became the single destination
/// control; they stay in-tree so their removal can be its own reviewable
/// change. `TopNavigationPillMetrics` is still the source of truth for the pill
/// widths their tests assert.
enum TopNavigationPillMetrics {
  static let itemSpacing: CGFloat = 4
  static let horizontalPadding: CGFloat = 12
  static let height: CGFloat = 30
  static let iconWidth: CGFloat = 18
  static let badgeWidth: CGFloat = 38

  static func width(for itemIndex: Int, badgeCount: Int = 0) -> CGFloat {
    let baseWidth: CGFloat
    switch itemIndex {
    case SidebarNavItem.dashboard.rawValue:
      baseWidth = 88
    case SidebarNavItem.conversations.rawValue:
      baseWidth = 128
    case SidebarNavItem.tasks.rawValue:
      baseWidth = 84
    case SidebarNavItem.apps.rawValue:
      baseWidth = 80
    default:
      baseWidth = 88
    }
    return baseWidth + (badgeCount > 0 ? badgeWidth : 0)
  }
}

private struct TopNavigationPill: View {
  let icon: String
  let title: String
  let badgeCount: Int
  let isSelected: Bool
  let width: CGFloat
  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .frame(width: TopNavigationPillMetrics.iconWidth)
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .semibold)
      if badgeCount > 0 {
        Text("+\(badgeCount)")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(OmiColors.textPrimary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Capsule(style: .continuous).fill(OmiColors.textPrimary.opacity(0.16)))
      }
    }
    .foregroundStyle(isSelected || isHovering ? OmiColors.textPrimary : OmiColors.textTertiary)
    .padding(.horizontal, TopNavigationPillMetrics.horizontalPadding)
    .frame(width: width, height: TopNavigationPillMetrics.height)
    .background(
      Capsule(style: .continuous)
        .fill(
          isSelected
            ? OmiColors.textPrimary.opacity(0.10)
            : isHovering ? OmiColors.textPrimary.opacity(0.06) : Color.clear
        )
    )
    .contentShape(Capsule())
    .onHover { isHovering = $0 }
  }
}

private struct MemoryDropdownRow: View {
  let destination: MemoryHubDestination
  let isSelected: Bool
  let width: CGFloat
  let onSelect: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 6) {
        Image(systemName: destination.icon)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .frame(width: TopNavigationPillMetrics.iconWidth)
        Text(destination.title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
      }
      .foregroundStyle(
        isSelected || isHovering ? OmiColors.textPrimary : OmiColors.textSecondary
      )
      .padding(.horizontal, TopNavigationPillMetrics.horizontalPadding)
      .frame(width: width, height: TopNavigationPillMetrics.height)
      .background(
        Capsule(style: .continuous)
          .fill(
            isSelected
              ? OmiColors.backgroundTertiary
              : isHovering ? OmiColors.backgroundTertiary : OmiColors.backgroundSecondary
          )
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(OmiColors.border.opacity(0.55), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.24), radius: 8, y: 3)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityIdentifier("memory-destination-\(destination.rawValue)")
  }
}
