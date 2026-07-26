import XCTest

@testable import Omi_Computer

@MainActor
final class AppsPageInstallScopeTests: XCTestCase {
  private func filteredProvider(installedOnly: Bool) -> AppProvider {
    let provider = AppProvider()
    provider.searchQuery = "notes"
    provider.selectedCategory = "productivity"
    provider.selectedCapability = "chat"
    provider.showInstalledOnly = installedOnly
    return provider
  }

  /// The segmented control's "All" segment must widen the scope only. Sending it
  /// through `clearFilters()` would wipe the search text and category the user
  /// can still see in the header.
  func testSelectingAllScopeKeepsEveryOtherFilter() {
    let provider = filteredProvider(installedOnly: true)

    provider.applyInstallScope(
      installedOnly: AppsPageInstallScope.installedOnly(forSelectionIndex: AppsPageInstallScope.all.rawValue)
    )

    XCTAssertFalse(provider.showInstalledOnly)
    XCTAssertEqual(provider.searchQuery, "notes")
    XCTAssertEqual(provider.selectedCategory, "productivity")
    XCTAssertEqual(provider.selectedCapability, "chat")
    XCTAssertTrue(provider.hasActiveFilters)
  }

  func testSelectingInstalledScopeKeepsEveryOtherFilter() {
    let provider = filteredProvider(installedOnly: false)

    provider.applyInstallScope(
      installedOnly: AppsPageInstallScope.installedOnly(forSelectionIndex: AppsPageInstallScope.installed.rawValue)
    )

    XCTAssertTrue(provider.showInstalledOnly)
    XCTAssertEqual(provider.searchQuery, "notes")
    XCTAssertEqual(provider.selectedCategory, "productivity")
    XCTAssertEqual(provider.selectedCapability, "chat")
  }

  func testInstallScopeRoundTripsThroughTheSelectionIndex() {
    for scope in AppsPageInstallScope.allCases {
      let index = AppsPageInstallScope.selectionIndex(installedOnly: scope.installedOnly)
      XCTAssertEqual(index, scope.rawValue)
      XCTAssertEqual(AppsPageInstallScope.installedOnly(forSelectionIndex: index), scope.installedOnly)
      XCTAssertEqual(AppsPageInstallScope.scope(installedOnly: scope.installedOnly), scope)
    }
  }

  func testSegmentTitlesFollowTheScopeOrder() {
    XCTAssertEqual(AppsPageInstallScope.segmentTitles, ["All", "Installed"])
    XCTAssertEqual(AppsPageInstallScope.segmentTitles.count, AppsPageInstallScope.allCases.count)
  }

  func testUnknownSelectionIndexFallsBackToAll() {
    XCTAssertFalse(AppsPageInstallScope.installedOnly(forSelectionIndex: -1))
    XCTAssertFalse(AppsPageInstallScope.installedOnly(forSelectionIndex: 7))
  }

  func testInstalledScopeEmptyStateNamesTheScopeInsteadOfASearch() {
    let copy = AppsPageInstallScope.emptyStateCopy(scope: .installed, searchText: "   ")

    XCTAssertEqual(copy.icon, "arrow.down.circle")
    XCTAssertEqual(copy.title, "No installed apps")
    XCTAssertNotNil(copy.message)
  }

  func testAllScopeEmptyStateStaysTheBareNoAppsFoundMessage() {
    let copy = AppsPageInstallScope.emptyStateCopy(scope: .all, searchText: "")

    XCTAssertEqual(copy.icon, "magnifyingglass")
    XCTAssertEqual(copy.title, "No apps found")
    XCTAssertNil(copy.message)
  }

  func testSearchTextTakesOverBothScopesEmptyStates() {
    let all = AppsPageInstallScope.emptyStateCopy(scope: .all, searchText: "einstein")
    let installed = AppsPageInstallScope.emptyStateCopy(scope: .installed, searchText: "einstein")

    XCTAssertEqual(all.icon, "magnifyingglass")
    XCTAssertEqual(installed.icon, "magnifyingglass")
    XCTAssertNotEqual(all, installed)
    XCTAssertEqual(all.title, "No apps found")
    XCTAssertEqual(installed.title, "No installed apps found")
  }
}
