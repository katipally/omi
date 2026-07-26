import AppKit
import Combine
import OmiTheme
import SwiftUI

/// Owns one notch panel per display. The notch is a passive voice surface: it
/// has no panel to open and nothing to auto-close, so a panel derives what it
/// shows entirely from `NotchPresentation` inside the view and idle CPU stays
/// at ~0%.
///
/// The one pointer-driven behaviour is the outside click: while a card or a
/// finished reply is on screen, a click anywhere else puts it away. Its monitors
/// live here rather than in the view because NSEvent monitors are process-wide —
/// one per panel would fire once per display for a single click — and because
/// stop / hide / snooze all pass through this object, which is what keeps them
/// from outliving the panels they speak for.
@MainActor
final class NotchScreenManager {
  private struct Panel {
    let window: NotchWindow
    let vm: NotchViewModel
  }

  private var panels: [CGDirectDisplayID: Panel] = [:]
  private var screenObserver: NSObjectProtocol?
  private var appActivationObserver: NSObjectProtocol?
  private var rebuildTask: Task<Void, Never>?
  private var outsideClick: NotchOutsideClickDismiss?
  private var cancellables = Set<AnyCancellable>()
  private var armingRefreshScheduled = false

  private weak var barState: FloatingControlBarState?

  /// Whether panels should be on screen. Panels are created hidden; only
  /// `showAll` (reached through show / snooze-clear / temporary-notification)
  /// reveals them, so a disabled or snoozed launch never flashes the notch.
  /// Consulted on display hot-plug so a newly attached screen matches the
  /// current visibility instead of always ordering front.
  private var panelsVisible = false

  /// System agents that present permission/auth dialogs. While one of these is
  /// frontmost, panels drop below dialog level so the prompt is never hidden
  /// behind the notch. Lowercased so the membership check can't be broken by a
  /// casing mismatch.
  private nonisolated static let systemDialogAgents: Set<String> = [
    "com.apple.usernotificationcenter",  // TCC permission alerts
    "com.apple.securityagent",  // keychain / authorization
    "com.apple.coreservices.uiagent",  // gatekeeper & consent prompts
    "com.apple.corelocationagent",
    "com.apple.universalaccessauthwarn",  // accessibility "control this computer" prompt
  ]

  func start(barState: FloatingControlBarState) {
    self.barState = barState
    outsideClick = NotchOutsideClickDismiss(
      notchWindows: { [weak self] in self?.panelWindows ?? [] },
      isSuppressed: { [weak self] in self?.isOutsideClickSuppressed ?? true },
      onOutsideClick: { [weak self] in self?.dismissForOutsideClick() }
    )
    rebuild()

    // The arming gate is coarse on purpose: it asks only whether anything on
    // screen could answer a click, and the ladder decides what a click actually
    // does at the moment it arrives. Coalesced through one hop, because the
    // reply that arms it publishes on every streamed token.
    barState.objectWillChange
      .sink { [weak self] _ in self?.scheduleArmingRefresh() }
      .store(in: &cancellables)

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.scheduleRebuild() }
    }

    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
        .bundleIdentifier
      let yields = bundleID.map { Self.systemDialogAgents.contains($0.lowercased()) } ?? false
      Task { @MainActor in
        guard let self else { return }
        for (_, panel) in self.panels {
          panel.window.setYieldsToSystemDialog(yields)
        }
      }
    }
  }

  func stop() {
    rebuildTask?.cancel()
    cancellables.removeAll()
    outsideClick?.disarm()
    outsideClick = nil
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
    }
    if let appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
    }
    for (_, panel) in panels {
      panel.window.orderOut(nil)
    }
    panels.removeAll()
  }

  /// The retired cross-panel linger dismissal. Nothing in Sources or Tests calls
  /// it: Esc is handled by the per-panel monitors in `NotchView`, which reach
  /// `NotchViewModel.dismissReply` directly, a new turn clears the previous reply
  /// through `resetReply` on the panel that owns it, and an outside click goes
  /// through the presentation ladder rather than this blanket fan-out. It stays
  /// in-tree so its removal can be its own reviewable change.
  func dismissLingeringReply() {
    for (_, panel) in panels where panel.vm.isLingeringReply {
      OmiMotion.withGated(NotchAnimation.close) { panel.vm.dismissReply() }
    }
  }

  /// Whether any panel is still holding a finished reply. Half of the
  /// outside-click arming gate: a lingering reply is something a click can put
  /// away, so the monitors are worth their keep while one is on screen.
  var hasLingeringReply: Bool {
    panels.values.contains { $0.vm.isLingeringReply }
  }

  /// Count of panels currently ordered on screen. The regression guard for the
  /// disabled/snoozed launch path: panels must stay at 0 until `showAll`.
  var visibleWindowCount: Int {
    panels.values.filter { $0.window.isVisible }.count
  }

  /// The panel on the screen under the pointer. nil before any panel exists.
  /// Automation captures the notch through this — the panel is the notch's only
  /// window, so a screenshot has to come from here rather than from the retired
  /// floating bar.
  var primaryPanel: NotchWindow? {
    let pointer = NSEvent.mouseLocation
    let target =
      panels.values.first { $0.vm.screenFrame.contains(pointer) }
      ?? panels[CGMainDisplayID()]
      ?? panels.values.first
    return target?.window
  }

  /// Order every panel back on screen (show / clearing snooze).
  func showAll() {
    panelsVisible = true
    applyPanelVisibility()
  }

  /// Order every panel off screen (hide / snooze / disable).
  func hideAll() {
    panelsVisible = false
    applyPanelVisibility()
  }

  private func applyPanelVisibility() {
    for panel in panels.values {
      if panelsVisible {
        panel.window.orderFrontRegardless()
      } else {
        panel.window.orderOut(nil)
      }
    }
    refreshOutsideClickArming()
  }

  // MARK: - Outside click

  private var panelWindows: [NSWindow] {
    panels.values.map { $0.window }
  }

  /// What a panel is showing right now, on the same ladder the view renders
  /// from — including the linger overlay, so a finished reply is still a reply
  /// here and not the idle chrome it will become.
  private func presentation(for panel: Panel) -> NotchPresentation {
    guard let barState else { return .idle }
    return NotchPresentation.resolve(
      isListening: barState.isListeningPhase,
      isThinking: barState.isThinking,
      isResponding: barState.isVoiceResponseActive,
      hintText: barState.notchHintText,
      notificationID: barState.currentNotification?.id,
      isVoiceDisplay: barState.voiceDisplayID.map { $0 == panel.vm.displayID } ?? true,
      isLingeringReply: panel.vm.isLingeringReply
    )
  }

  /// A tracking menu owns the click that closes it — usually the notch's own
  /// context menu, whose card would otherwise be dismissed by the same click
  /// that put the menu away.
  private var isOutsideClickSuppressed: Bool {
    panels.values.contains { $0.window.isMenuTracking }
  }

  /// Put away whatever the click was not aimed at. Dismissal only: the card's
  /// own buttons are the only things that retry, undo or delete, and a click
  /// that landed somewhere else is not a choice between them.
  private func dismissForOutsideClick() {
    var dismissesNotification = false
    let voiceTurnActive = barState?.isVoicePresentationActive ?? false

    for panel in panels.values {
      switch presentation(for: panel).outsideClickOutcome(isVoiceTurnActive: voiceTurnActive) {
      case .ignored:
        continue
      case .lingeringReply:
        OmiMotion.withGated(NotchAnimation.close) { panel.vm.dismissReply() }
      case .notification:
        dismissesNotification = true
      }
    }

    // One card slot for the whole app, so this is one call however many panels
    // were showing it. A card queued behind it takes its place.
    if dismissesNotification {
      FloatingControlBarManager.shared.dismissCurrentNotification()
    }
    refreshOutsideClickArming()
  }

  /// `objectWillChange` fires before the value lands, so the refresh has to run
  /// a turn later; the flag keeps a burst of publishes to a single one.
  private func scheduleArmingRefresh() {
    guard !armingRefreshScheduled else { return }
    armingRefreshScheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      armingRefreshScheduled = false
      refreshOutsideClickArming()
    }
  }

  private func refreshOutsideClickArming() {
    let hasDismissibleSurface = barState?.currentNotification != nil || hasLingeringReply
    if panelsVisible, hasDismissibleSurface {
      outsideClick?.arm()
    } else {
      outsideClick?.disarm()
    }
  }

  // MARK: - Panel lifecycle

  /// Display hot-plug/sleep fires bursts of change notifications; settle first.
  private func scheduleRebuild() {
    rebuildTask?.cancel()
    rebuildTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(0.5))
      guard !Task.isCancelled else { return }
      self?.rebuild()
    }
  }

  private func rebuild() {
    var seen: Set<CGDirectDisplayID> = []

    for screen in NSScreen.screens {
      let id = screen.omiDisplayID
      seen.insert(id)
      if let panel = panels[id] {
        panel.vm.refresh(for: screen)
      } else {
        panels[id] = makePanel(for: screen)
      }
    }

    for (id, panel) in panels where !seen.contains(id) {
      panel.window.orderOut(nil)
      panels.removeValue(forKey: id)
    }

    // A voice turn latched to a display that just went away would leave every
    // remaining panel suppressed.
    barState?.clearVoiceDisplayID(unless: seen)

    // Newly created panels start hidden; a screen attached while the notch is
    // visible is surfaced here.
    applyPanelVisibility()
  }

  private func makePanel(for screen: NSScreen) -> Panel {
    let vm = NotchViewModel(screen: screen)
    let window = NotchWindow(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
      backing: .buffered,
      defer: false
    )
    let root = NotchView(vm: vm)
      .environmentObject(barState ?? FloatingControlBarState())
    window.contentView = NotchHostingView(rootView: AnyView(root))
    vm.attach(window: window)
    // Created hidden. Visibility is owned by applyPanelVisibility so the
    // persisted enabled/snoozed/deferred launch state is respected.
    return Panel(window: window, vm: vm)
  }
}
