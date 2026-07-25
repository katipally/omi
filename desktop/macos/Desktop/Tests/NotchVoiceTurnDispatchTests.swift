import XCTest

@testable import Omi_Computer

/// A spoken turn must dispatch when the notch is the surface.
///
/// Regression: the notch replaced the legacy single-window bar, but the PTT
/// submit path still required that window. With no window the query was never
/// routed, so the notch showed the thinking spinner, timed out, and dropped
/// back to listening — a turn that never went anywhere.
@MainActor
final class NotchVoiceTurnDispatchTests: XCTestCase {
  func testNotchSetupBindsTheChatProviderTheVoicePathDispatchesThrough() {
    let manager = FloatingControlBarManager.shared
    let provider = ChatProvider.mainInstance ?? ChatProvider()

    manager.setup(appState: AppState(), chatProvider: provider)

    // `activeFloatingProvider()` gates every spoken turn. It reads this
    // binding, which used to be made only while building the legacy window.
    XCTAssertNotNil(
      manager.sharedFloatingProvider,
      "Notch setup must bind the chat provider; without it every voice turn is dropped before dispatch")
  }

  func testAutomationStateReportsTheNotchRatherThanTheRetiredWindow() {
    // Regression: automationState still guarded on the legacy window, so with
    // the notch running every reader — `omi-ctl state`, the e2e flows, the
    // bridge actions — saw a bar that was never visible and refused to drive it.
    let manager = FloatingControlBarManager.shared
    manager.setup(appState: AppState(), chatProvider: ChatProvider.mainInstance ?? ChatProvider())

    XCTAssertNil(manager.window, "The notch surface does not build the legacy window")
    XCTAssertNotNil(
      manager.automationState.frame,
      "Automation must report the notch panel's frame, not nil from the absent window")
  }

  func testBarStateResolvesToTheNotchStateOnceTheNotchIsRunning() {
    let manager = FloatingControlBarManager.shared
    manager.setup(appState: AppState(), chatProvider: ChatProvider.mainInstance ?? ChatProvider())

    // Everything upstream of the surface — PTT, the realtime hub, the voice
    // projection applier — reads `barState`. If it does not resolve while the
    // notch is running, the turn renders into a state nothing is observing.
    XCTAssertNotNil(manager.barState)
    XCTAssertTrue(
      manager.barState === manager.notchState,
      "With the notch running, barState must be the state its panels observe")
  }
}
