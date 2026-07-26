import XCTest

@testable import Omi_Computer

/// Regression coverage for the apps catalog's install decisions: the
/// detail-sheet primary action, the card control's visual treatment, and the
/// enabled-state lookup all three of them read.
///
/// `AppDetailSheet.primaryAppAction`: the detail-sheet
/// primary button previously derived its label and its action independently, an
/// enabled non-external app showed an "Open" label whose action fell through to a
/// destructive `toggleApp` (disable), silently uninstalling the app on tap. The
/// action is now derived once from (isEnabled, worksExternally) so label and
/// behavior cannot diverge.
final class AppsPagePrimaryActionTests: XCTestCase {

  func testNotEnabledInstalls() {
    XCTAssertEqual(
      AppDetailSheet.primaryAppAction(isEnabled: false, worksExternally: false), .install)
    XCTAssertEqual(
      AppDetailSheet.primaryAppAction(isEnabled: false, worksExternally: true), .install)
  }

  func testEnabledExternalOpens() {
    XCTAssertEqual(
      AppDetailSheet.primaryAppAction(isEnabled: true, worksExternally: true), .open)
  }

  func testEnabledNonExternalHasNoPrimaryAction() {
    // The regression case: previously "Open" → destructive disable. There is
    // no open target for an enabled non-external app, so no primary button.
    XCTAssertEqual(
      AppDetailSheet.primaryAppAction(isEnabled: true, worksExternally: false), .hidden)
  }

  // MARK: - Install control treatment

  /// An installed and a not-installed card resolved to byte-identical controls
  /// whose only difference was the word inside them, so the grid could not be
  /// scanned for what was already installed.
  func testInstalledAndNotInstalledResolveToDifferentTreatments() {
    let notInstalled = AppInstallDecision.treatment(for: .install)
    let installed = AppInstallDecision.treatment(for: .open)

    XCTAssertNotEqual(notInstalled, installed)
    XCTAssertTrue(notInstalled.isFilled)
    XCTAssertFalse(installed.isFilled)
  }

  func testControlDerivesFromEnabledAndLoadingState() {
    XCTAssertEqual(AppInstallDecision.control(isEnabled: false, isLoading: false), .install)
    XCTAssertEqual(AppInstallDecision.control(isEnabled: true, isLoading: false), .open)
    XCTAssertEqual(AppInstallDecision.control(isEnabled: false, isLoading: true), .installing)
    XCTAssertEqual(AppInstallDecision.control(isEnabled: true, isLoading: true), .removing)
  }

  /// In flight, the control used to become a bare spinner that named neither the
  /// work nor its direction.
  func testInFlightTreatmentsNameTheWork() {
    let installing = AppInstallDecision.treatment(for: .installing)
    let removing = AppInstallDecision.treatment(for: .removing)

    XCTAssertTrue(installing.showsProgress)
    XCTAssertTrue(removing.showsProgress)
    XCTAssertEqual(installing.title, "Installing")
    XCTAssertEqual(removing.title, "Removing")
  }

  // MARK: - Enabled resolution

  /// An app opened from a search result lives only in `filteredApps`. Reading
  /// the loaded catalog alone left the sheet on the captured `enabled: false`
  /// forever, so its button never flipped to "Open" and the install path pushed
  /// an already-enabled app into setup.
  func testEnabledResolutionFindsSearchOnlyApp() throws {
    let searchResult = try makeApp(id: "search-only", enabled: true)

    XCTAssertTrue(
      AppInstallDecision.resolvedEnabled(
        appId: "search-only",
        capturedEnabled: false,
        installedApps: [],
        filteredApps: [searchResult]
      ))
  }

  func testEnabledResolutionPrefersCatalogOverCapturedValue() throws {
    let catalogApp = try makeApp(id: "catalog", enabled: false)

    XCTAssertFalse(
      AppInstallDecision.resolvedEnabled(
        appId: "catalog",
        capturedEnabled: true,
        installedApps: [catalogApp],
        filteredApps: nil
      ))
  }

  func testEnabledResolutionFallsBackToCapturedValue() {
    XCTAssertTrue(
      AppInstallDecision.resolvedEnabled(
        appId: "unknown",
        capturedEnabled: true,
        installedApps: [],
        filteredApps: nil
      ))
  }

  private func makeApp(id: String, enabled: Bool) throws -> OmiApp {
    let json = """
      {"id": "\(id)", "name": "App \(id)", "enabled": \(enabled)}
      """.data(using: .utf8)!
    return try JSONDecoder().decode(OmiApp.self, from: json)
  }
}
