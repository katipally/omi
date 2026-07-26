import OmiTheme
import SwiftUI

/// The Capture + Listening status controls in the shell top bar. This is the
/// only copy the app renders, and it is present on every page including Home;
/// `DashboardPage.homeHeader` is a retired second copy with no call site.
///
/// Hovering Capture reveals a Rewind shortcut beneath it; hovering Listening
/// reveals the three capture modes. Both are overlays, so revealing one never
/// reflows the bar.
///
/// The toggle logic lives in `CaptureListeningLogic` and drives the shared
/// singletons (`AssistantSettings`, `ProactiveAssistantsPlugin`, `AppState`).
struct CaptureListeningControls: View {
  @ObservedObject var appState: AppState
  var onRewind: () -> Void

  @State private var isCaptureMonitoring = false
  @State private var isTogglingCapture = false
  @State private var isTogglingListening = false
  @State private var hoverCapture = false
  @State private var hoverRewind = false
  @State private var hoverListening = false
  @State private var hoverListeningModes = false

  @AppStorage("screenAnalysisEnabled") private var screenAnalysisEnabled = true
  @AppStorage("transcriptionEnabled") private var transcriptionEnabled = true
  @AppStorage("systemAudioCaptureMode") private var systemAudioCaptureModeRaw =
    AssistantSettings.SystemAudioCaptureMode.onlyDuringMeetings.rawValue

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      captureButton
      listeningButton
    }
    .onAppear(perform: syncCaptureState)
    .onReceive(NotificationCenter.default.publisher(for: .screenCapturePermissionLost)) { _ in
      syncCaptureState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .screenCaptureKitBroken)) { _ in
      syncCaptureState()
    }
  }

  /// The retired transcription-failure flag. Nothing reads it since the chip
  /// started deriving every state from `ListeningChipState`, which folds the
  /// service error in alongside the capture gate; it stays in-tree so its
  /// removal can be its own reviewable change.
  private var transcriptionUnavailable: Bool { appState.transcriptionServiceError != nil }

  // MARK: Capture button + hover Rewind affordance

  private var captureButton: some View {
    HomeStatusButton(
      title: "Capture",
      systemImage: "viewfinder",
      status: captureStatus,
      isToggling: isTogglingCapture,
      action: toggleCapture
    )
    .onHover { hoverCapture = $0 }
    .overlay(alignment: .top) {
      if hoverCapture || hoverRewind {
        rewindChip
          .offset(y: 34)
          .transition(.opacity)
      }
    }
    .omiAnimation(.easeOut(duration: 0.12), value: hoverCapture || hoverRewind)
  }

  private var rewindChip: some View {
    // A small transparent bridge on top keeps the chip open while the cursor
    // travels down from the Capture pill into it.
    VStack(spacing: 0) {
      Color.clear.frame(height: 6)
      Button(action: onRewind) {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "clock.arrow.circlepath")
            .scaledFont(size: OmiType.caption, weight: .semibold)
          Text("Rewind")
            .scaledFont(size: OmiType.caption, weight: .semibold)
        }
        .foregroundStyle(OmiColors.textPrimary)
        .padding(.horizontal, OmiSpacing.md)
        .frame(height: 30)
        .background(Capsule(style: .continuous).fill(OmiColors.backgroundTertiary))
        .overlay(Capsule(style: .continuous).stroke(OmiColors.textPrimary.opacity(0.12), lineWidth: 1))
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .help("Open Rewind")
      .accessibilityLabel("Open Rewind")
    }
    .onHover { hoverRewind = $0 }
    .fixedSize()
  }

  // MARK: Listening button + hover mode picker

  private var listeningButton: some View {
    // The title is a constant so a transcription failure cannot widen the chip
    // and shove the rest of the cluster sideways; the failure shows up in the
    // icon, the tooltip and the VoiceOver label instead.
    HomeListeningStatusButton(
      title: "Listening",
      systemImage: listeningChipState.systemImage,
      status: listeningChipState.statusState,
      modeTitle: listeningModeTitle,
      isMeetingsOnly: listeningCaptureMode == .onlyDuringMeetings,
      isToggling: isTogglingListening,
      action: toggleListening,
      modeAction: toggleListeningMode,
      chipState: listeningChipState,
      modeBadge: listeningModeBadge,
      modeOptions: listeningModeOptions,
      setMode: setListeningMode,
      cycleMode: cycleListeningMode
    )
    .onHover { hoverListening = $0 }
    .overlay(alignment: HoverRevealAnchor.chipTrailing.overlayAlignment) {
      if hoverListening || hoverListeningModes {
        listeningModeChip
          .offset(y: 34)
          .transition(.opacity)
      }
    }
    .omiAnimation(.easeOut(duration: 0.12), value: hoverListening || hoverListeningModes)
  }

  private var listeningModeChip: some View {
    // Same transparent bridge as Rewind: the cursor has to cross 6pt of gap to
    // reach the picker, and losing hover mid-travel would snap it shut.
    VStack(spacing: 0) {
      Color.clear.frame(height: 6)
      VStack(spacing: 0) {
        ForEach(listeningModeOptions) { option in
          if option.id != listeningModeOptions.first?.id {
            Rectangle()
              .fill(OmiColors.textPrimary.opacity(0.08))
              .frame(height: 1)
          }
          ListeningModeRow(option: option) { setListeningMode(option.mode) }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(OmiColors.backgroundTertiary)
      )
      .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .stroke(OmiColors.textPrimary.opacity(0.12), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.30), radius: 16, y: 8)
    }
    .onHover { hoverListeningModes = $0 }
    .fixedSize()
  }

  // MARK: Derived state (mirrors DashboardPage)

  private var captureStatus: HomeStatusState {
    CaptureListeningLogic.captureStatus(appState: appState, isCaptureMonitoring: isCaptureMonitoring)
  }

  private var isCaptureLive: Bool {
    CaptureListeningLogic.isCaptureLive(isCaptureMonitoring: isCaptureMonitoring)
  }

  private var listeningCaptureMode: AssistantSettings.SystemAudioCaptureMode {
    CaptureListeningLogic.listeningCaptureMode(raw: systemAudioCaptureModeRaw)
  }

  private var listeningChipState: ListeningChipState {
    CaptureListeningLogic.listeningChipState(appState: appState)
  }

  private var listeningModeTitle: String {
    CaptureListeningLogic.listeningModeTitle(appState: appState, raw: systemAudioCaptureModeRaw)
  }

  private var listeningModeBadge: String? {
    CaptureListeningLogic.listeningModeBadge(
      mode: listeningCaptureMode,
      isTranscribing: appState.isTranscribing,
      isAwaitingMeeting: appState.isAwaitingMeeting
    )
  }

  private var listeningModeOptions: [ListeningModeOption] {
    CaptureListeningLogic.listeningModeOptions(current: listeningCaptureMode)
  }

  // MARK: Actions (shared with DashboardPage via CaptureListeningLogic)

  private func toggleListening() {
    CaptureListeningLogic.toggleListening(
      appState: appState, transcriptionEnabled: $transcriptionEnabled, isTogglingListening: $isTogglingListening)
  }

  private func toggleListeningMode() {
    CaptureListeningLogic.toggleListeningMode(raw: $systemAudioCaptureModeRaw)
  }

  private func setListeningMode(_ mode: AssistantSettings.SystemAudioCaptureMode) {
    CaptureListeningLogic.setListeningMode(mode, raw: $systemAudioCaptureModeRaw)
  }

  private func cycleListeningMode() {
    CaptureListeningLogic.cycleListeningMode(raw: $systemAudioCaptureModeRaw)
  }

  private func toggleCapture() {
    CaptureListeningLogic.toggleCapture(
      appState: appState, screenAnalysisEnabled: $screenAnalysisEnabled,
      isCaptureMonitoring: $isCaptureMonitoring, isTogglingCapture: $isTogglingCapture)
  }

  private func syncCaptureState() {
    CaptureListeningLogic.syncCaptureState(
      screenAnalysisEnabled: $screenAnalysisEnabled, isCaptureMonitoring: $isCaptureMonitoring)
  }
}

/// Which point on its chip a top-bar hover reveal hangs from.
///
/// A reveal is an overlay on its chip, so a panel wider than the chip has to
/// spill somewhere: anchored at the chip's centre it spills half the difference
/// past each side. A chip with room on both sides can afford that; the chip
/// pinned to the bar's trailing edge cannot, because half the spill lands
/// outside the window. `chipTrailing` grows the panel inward instead.
enum HoverRevealAnchor {
  case chipCenter
  case chipTrailing

  /// Where along a width the anchor sits. `overlayAlignment` hands SwiftUI the
  /// same fraction, so the two cannot describe different placements.
  var unitPoint: CGFloat {
    switch self {
    case .chipCenter: return 0.5
    case .chipTrailing: return 1
    }
  }

  var overlayAlignment: Alignment {
    switch self {
    case .chipCenter: return .top
    case .chipTrailing: return .topTrailing
    }
  }

  /// The x-range the panel occupies in the top bar's content coordinates. The
  /// Listening chip ends flush with that content's trailing edge, so
  /// `containerWidth` doubles as the chip's own trailing edge.
  func panelBounds(chipWidth: CGFloat, panelWidth: CGFloat, containerWidth: CGFloat)
    -> ClosedRange<CGFloat>
  {
    let width = max(0, panelWidth)
    let anchorX = containerWidth - chipWidth + chipWidth * unitPoint
    let minX = anchorX - width * unitPoint
    return minX...(minX + width)
  }
}

/// One row of the hover-revealed listening-mode picker. The checkmark sits in a
/// fixed-width slot so moving the selection never shifts the labels.
private struct ListeningModeRow: View {
  let option: ListeningModeOption
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: OmiSpacing.sm) {
        ZStack {
          if option.isCurrent {
            Image(systemName: "checkmark")
              .scaledFont(size: OmiType.micro, weight: .bold)
              .foregroundStyle(OmiColors.textPrimary)
          }
        }
        .frame(width: 12, height: 14)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(option.title)
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundStyle(option.isCurrent ? OmiColors.textPrimary : OmiColors.textSecondary)

          Text(option.detail)
            .scaledFont(size: OmiType.micro)
            .foregroundStyle(OmiColors.textTertiary)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(minWidth: 224, alignment: .leading)
      .background(isHovering ? OmiColors.textPrimary.opacity(0.07) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .omiAnimation(.easeOut(duration: 0.12), value: isHovering)
    .help(option.detail)
    .accessibilityLabel("\(option.title). \(option.detail)")
    .accessibilityAddTraits(option.isCurrent ? [.isButton, .isSelected] : .isButton)
  }
}
