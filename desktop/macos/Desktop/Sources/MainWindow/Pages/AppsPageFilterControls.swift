import OmiTheme
import SwiftUI

enum AppsPageCategoryFilter {
  static let allCategoriesOptionId = ""
  static let allCategoriesTitle = "All Categories"

  enum Selection: Equatable {
    case allCategories
    case category(String)
  }

  static func categoryDropdownOptions(categories: [OmiAppCategory]) -> [SearchableDropdownOption] {
    [SearchableDropdownOption(id: allCategoriesOptionId, title: allCategoriesTitle)]
      + categories.map { SearchableDropdownOption(id: $0.id, title: $0.title) }
  }

  static func selectedCategoryDropdownId(_ selectedCategory: String?) -> String {
    selectedCategory ?? allCategoriesOptionId
  }

  static func categorySelection(forOptionId optionId: String) -> Selection {
    optionId.isEmpty ? .allCategories : .category(optionId)
  }
}

/// The two scopes the catalog can be browsed in. Naming them is what lets the
/// header render a segmented control: an on/off chip over a `Bool` can only ever
/// show one of the two choices, so the resting state read as "no filter" when it
/// was in fact "everything".
enum AppsPageInstallScope: Int, CaseIterable {
  case all
  case installed

  var title: String {
    switch self {
    case .all: return "All"
    case .installed: return "Installed"
    }
  }

  /// The catalog filter is served by the API, which takes this one flag.
  var installedOnly: Bool { self == .installed }

  static var segmentTitles: [String] { allCases.map(\.title) }

  static func scope(installedOnly: Bool) -> AppsPageInstallScope {
    installedOnly ? .installed : .all
  }

  static func selectionIndex(installedOnly: Bool) -> Int {
    scope(installedOnly: installedOnly).rawValue
  }

  static func installedOnly(forSelectionIndex index: Int) -> Bool {
    (AppsPageInstallScope(rawValue: index) ?? .all).installedOnly
  }

  struct EmptyStateCopy: Equatable {
    let icon: String
    let title: String
    let message: String?
  }

  /// Owning zero apps is an ordinary state once "Installed" is a scope the user
  /// picks on purpose, so the empty view names that scope instead of reporting a
  /// search that found nothing.
  static func emptyStateCopy(scope: AppsPageInstallScope, searchText: String) -> EmptyStateCopy {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.isEmpty else {
      return EmptyStateCopy(
        icon: "magnifyingglass",
        title: scope == .installed ? "No installed apps found" : "No apps found",
        message: scope == .installed
          ? "Nothing you have installed matches that search."
          : "Try a different search term."
      )
    }

    switch scope {
    case .all:
      return EmptyStateCopy(icon: "magnifyingglass", title: "No apps found", message: nil)
    case .installed:
      return EmptyStateCopy(
        icon: "arrow.down.circle",
        title: "No installed apps",
        message: "Apps you install show up here."
      )
    }
  }
}

// MARK: - Header Row

enum AppsHeaderMetrics {
  /// Wide enough for a real query, narrow enough that the scope and category
  /// controls keep their labels on a standard window.
  static let searchFieldMaxWidth: CGFloat = 340
}

/// The Apps catalog header: search, install scope, category, create, dismiss.
///
/// The search field is the only flexible control in the row, so it has to be
/// capped. Given a free rein it claimed the whole width and squeezed its
/// labelled neighbours down to their truncation width — which is how the
/// All / Installed segments rendered as an empty blob with no text in them at
/// all. Capping the field and fixing the labelled controls horizontally makes
/// the row incompressible below its legible size at any window width, and the
/// stacked arm takes over from there.
struct AppsHeaderRow<Search: View, Filters: View, Create: View, Dismiss: View>: View {
  let search: Search
  let filters: Filters
  let create: Create
  let dismiss: Dismiss

  init(
    @ViewBuilder search: () -> Search,
    @ViewBuilder filters: () -> Filters,
    @ViewBuilder create: () -> Create,
    @ViewBuilder dismiss: () -> Dismiss
  ) {
    self.search = search()
    self.filters = filters()
    self.create = create()
    self.dismiss = dismiss()
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: OmiSpacing.md) {
        search
          .frame(maxWidth: AppsHeaderMetrics.searchFieldMaxWidth)
        filters
          .fixedSize(horizontal: true, vertical: false)
        create
        dismiss
      }

      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.sm) {
          search
          dismiss
        }

        HStack(spacing: OmiSpacing.sm) {
          filters
            .fixedSize(horizontal: true, vertical: false)
          create
        }
      }
    }
  }
}

// MARK: - Filter Toggle

/// Retired: the header's install scope is an `OmiSegmentedControl` over
/// `AppsPageInstallScope`. Nothing constructs this any more; it stays in-tree so
/// its removal can be its own reviewable change.
struct FilterToggle: View {
  let icon: String
  let label: String
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      OmiFilterChip(icon: icon, title: label, isActive: isActive)
        .fixedSize(horizontal: true, vertical: false)
    }
    .buttonStyle(.plain)
  }
}
