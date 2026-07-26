import AppKit
import OmiTheme
import SwiftUI

/// Owns one notch panel per display. The notch is a passive voice surface: it
/// has no panel to open and nothing to auto-close, so there is no pointer
/// tracking at all and idle CPU stays at ~0%. What a panel shows is derived
/// entirely from `NotchPresentation` inside the view.
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
    rebuild()

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

  /// The retired cross-panel linger controls. Nothing in Sources or Tests calls
  /// either one: Esc is handled by the per-panel monitors in `NotchView`, which
  /// reach `NotchViewModel.dismissReply` directly, and a new turn clears the
  /// previous reply through `resetReply` on the panel that owns it — so there is
  /// no fan-out left to perform or query. Both stay in-tree so their removal can
  /// be its own reviewable change.
  func dismissLingeringReply() {
    for (_, panel) in panels where panel.vm.isLingeringReply {
      OmiMotion.withGated(NotchAnimation.close) { panel.vm.dismissReply() }
    }
  }

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
