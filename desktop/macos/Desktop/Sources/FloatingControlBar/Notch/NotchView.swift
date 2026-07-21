import SwiftUI

/// Root view for one notch panel. The window frame is fixed; this view derives
/// a `NotchPresentation` and animates ONLY the inner content frame + corner
/// radii, anchored `.top` so every expansion grows out of the notch.
struct NotchView: View {
  @ObservedObject var vm: NotchViewModel
  /// The shared main-chat provider; the notch renders its timeline directly.
  var chatProvider: ChatProvider?
  @EnvironmentObject var barState: FloatingControlBarState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isHovering = false

  // MARK: - Presentation ladder

  /// Single value that both the panel size and the rendered content derive
  /// from. Priority: open > listening > thinking > hint > notification > idle.
  private var presentation: NotchPresentation {
    if vm.state == .open { return .open(vm.selectedTab) }
    if barState.isVoiceListening { return .listening }
    if barState.isThinking { return .thinking }
    if !barState.pttHintText.isEmpty { return .hint(barState.pttHintText) }
    if let notification = barState.currentNotification { return .notification(notification.id) }
    return .idle
  }

  // MARK: - Animations (two isolated timelines)

  /// Discrete morphs: open/close/tab/voice/notification. Springs.
  private var morphAnimation: Animation {
    if reduceMotion { return .easeInOut(duration: 0.25) }
    switch presentation {
    case .open: return NotchAnimation.open
    case .idle, .listening, .thinking, .hint, .notification: return NotchAnimation.close
    }
  }

  /// Continuous auto-grow while an answer streams. Calm, no spring bounce.
  /// Deliberately isolated from the morph timeline: keying the morph spring on
  /// the measured height makes the measure->resize->remeasure loop oscillate.
  private var heightAnimation: Animation {
    reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.35)
  }

  private var contentTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
  }

  private var displayedSize: CGSize { vm.size(for: presentation) }

  private var topCornerRadius: CGFloat {
    presentation.isExpandedSurface ? NotchMetrics.cornerOpen.top : NotchMetrics.cornerClosed.top
  }

  private var bottomCornerRadius: CGFloat {
    presentation.isExpandedSurface ? NotchMetrics.cornerOpen.bottom : NotchMetrics.cornerClosed.bottom
  }

  // MARK: - Body

  var body: some View {
    ZStack(alignment: .top) {
      tray
      notchBody
    }
    .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
    .animation(morphAnimation, value: presentation)
    .animation(heightAnimation, value: vm.chatBodyHeight)
  }

  /// The floating composer glued below the body's bottom edge: it offsets by
  /// the displayed height, so it rides both animation timelines with the body.
  @ViewBuilder
  private var tray: some View {
    if vm.state == .open, let chatProvider {
      NotchTrayView(chatProvider: chatProvider)
        .frame(width: min(displayedSize.width - 24, 460))
        .offset(y: displayedSize.height + NotchMetrics.trayGap)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private var notchBody: some View {
    bodyContent
      .frame(width: displayedSize.width, height: displayedSize.height, alignment: .top)
      .background(.black)
      .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
      // 1pt seam hider: the top fillets must never reveal a hairline gap
      // against the physical black notch / bezel.
      .overlay(alignment: .top) {
        Rectangle()
          .fill(.black)
          .frame(height: 1)
          .padding(.horizontal, topCornerRadius)
      }
      .shadow(
        color: (vm.state == .open || isHovering) ? .black.opacity(0.7) : .clear,
        radius: 8
      )
      .contentShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
      .onHover(perform: handleHover)
      .onTapGesture(perform: handleTap)
      .onExitCommand {
        guard vm.state == .open else { return }
        withAnimation(NotchAnimation.close) { vm.close() }
      }
  }

  @ViewBuilder
  private var bodyContent: some View {
    switch presentation {
    case .open(let tab):
      VStack(spacing: 0) {
        headerRow
        openContent(for: tab)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
      }
      .clipped()
      .transition(contentTransition)
    case .listening, .thinking, .hint, .notification:
      // Voice + notification chrome lands in a later phase; until then these
      // presentations render the sized black surface.
      Color.black.transition(contentTransition)
    case .idle:
      closedChrome
    }
  }

  // MARK: - Closed chrome (always-visible Omi identity)

  private var closedChrome: some View {
    HStack(spacing: 0) {
      Button {
        withAnimation(NotchAnimation.open) { vm.open(tab: .agents) }
      } label: {
        NotchOmiMark()
          .frame(width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Omi agents")
      Color.clear
        .frame(width: max(0, vm.closedNotchSize.width - NotchMetrics.closedSideWidth * 2))
      settingsButton
        .frame(width: NotchMetrics.closedSideWidth, height: vm.closedNotchSize.height)
    }
    .frame(height: vm.closedNotchSize.height)
  }

  private var settingsButton: some View {
    Button(action: openSettings) {
      Image(systemName: "gearshape.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.7))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Omi settings")
  }

  // MARK: - Open header

  private var headerRow: some View {
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        ForEach(NotchTab.allCases) { tab in
          tabButton(tab)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // Camera void: header controls must never render under the physical
      // notch, so reserve the full closed-chrome width there.
      Color.clear
        .frame(width: vm.hasPhysicalNotch ? vm.closedNotchSize.width : NotchMetrics.headerCameraReserve)
      HStack(spacing: 6) {
        settingsButton
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .frame(height: vm.closedNotchSize.height)
  }

  private func tabButton(_ tab: NotchTab) -> some View {
    Button {
      withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : NotchAnimation.tab) {
        vm.selectedTab = tab
      }
    } label: {
      Image(systemName: tab.symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(vm.selectedTab == tab ? .white : .white.opacity(0.55))
        .frame(width: 30, height: 22)
        .background(
          Capsule().fill(vm.selectedTab == tab ? Color.white.opacity(0.14) : .clear)
        )
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(tab.label)
    .accessibilityLabel(tab.label)
  }

  @ViewBuilder
  private func openContent(for tab: NotchTab) -> some View {
    switch tab {
    case .chat:
      if let chatProvider {
        NotchChatView(chatProvider: chatProvider) { height in
          // 4pt jitter filter: sub-pixel measurement noise must not feed the
          // height animation or the measure loop oscillates.
          if abs((vm.chatBodyHeight ?? 0) - height) > 4 {
            vm.chatBodyHeight = height
          }
        }
      } else {
        Color.clear
      }
    case .agents:
      // Agents list lands in phase 4.
      Color.clear
    }
  }

  // MARK: - Interactions

  private func handleHover(_ hovering: Bool) {
    isHovering = hovering
    if hovering {
      vm.hoverEntered()
    } else {
      vm.hoverExited()
    }
  }

  /// Chat-first: any click on the closed chrome opens chat, except the logo
  /// which opens the agents list (and the gear, which is its own button).
  private func handleTap() {
    guard vm.state == .closed else { return }
    withAnimation(NotchAnimation.open) { vm.open(tab: .chat) }
  }

  private func openSettings() {
    NotificationCenter.default.post(name: .navigateToFloatingBarSettings, object: nil)
    (NSApp.delegate as? AppDelegate)?.openMainAppWindow()
  }
}
