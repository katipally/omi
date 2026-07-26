import AppKit
import Foundation

/// One backend-grant integration, mirroring the mobile app's `IntegrationApp`.
///
/// Apple Health is deliberately absent: it is a HealthKit integration with no
/// macOS surface. Everything else about the model matches the app so the two
/// clients cannot drift on what a grant means.
enum IntegrationGrant: String, CaseIterable, Identifiable, Sendable {
  case googleCalendar = "google_calendar"
  case gmail

  var id: String { rawValue }

  /// The key the backend routes on. Gmail has no grant of its own, but it does
  /// have its own status, so it is still asked for by its own key.
  var appKey: String { rawValue }

  var displayName: String {
    switch self {
    case .googleCalendar: return "Google Calendar"
    case .gmail: return "Gmail"
    }
  }

  var subtitle: String {
    switch self {
    case .googleCalendar: return "Let Omi read your events when it answers"
    case .gmail: return "Let Omi read your recent mail when it answers"
    }
  }

  var icon: String {
    switch self {
    case .googleCalendar: return "calendar"
    case .gmail: return "envelope.fill"
    }
  }

  /// Name shown in the disconnect confirmation. Gmail and Google Calendar share
  /// a single Google grant, so disconnecting either one drops both, and the
  /// confirmation has to say so.
  var disconnectDisplayName: String {
    switch self {
    case .gmail, .googleCalendar: return "Gmail and Google Calendar"
    }
  }
}

/// The three backend calls the grants UI makes, behind a seam so the store's
/// state transitions can be exercised without a server or a browser.
struct IntegrationGrantTransport: Sendable {
  var connected: @Sendable (String) async throws -> Bool
  var oauthURL: @Sendable (String) async throws -> URL
  var disconnect: @Sendable (String) async throws -> Void
  var openInBrowser: @Sendable (URL) async -> Bool

  static let live = IntegrationGrantTransport(
    connected: { try await APIClient.shared.integrationConnected(appKey: $0) },
    oauthURL: { try await APIClient.shared.integrationOAuthURL(appKey: $0) },
    disconnect: { try await APIClient.shared.disconnectIntegration(appKey: $0) },
    openInBrowser: { url in await MainActor.run { NSWorkspace.shared.open(url) } }
  )
}

@MainActor
final class IntegrationGrantStore: ObservableObject {
  /// Absent means "not read yet", which the row shows as neither connected nor
  /// disconnected. Defaulting to `false` would flash "Not connected" at a user
  /// whose grant is fine.
  @Published private(set) var connected: [IntegrationGrant: Bool] = [:]
  @Published private(set) var isLoading = false
  /// The one grant with a connect or disconnect in flight. Only one at a time:
  /// both rows drive the same Google grant, so a second concurrent flow would
  /// be racing the first over the same state.
  @Published private(set) var busy: IntegrationGrant?
  @Published var errorMessage: String?
  @Published var pendingDisconnect: IntegrationGrant?

  private let transport: IntegrationGrantTransport
  private let pollInterval: Duration
  private let pollAttempts: Int

  init(
    transport: IntegrationGrantTransport = .live,
    pollInterval: Duration = .seconds(2),
    pollAttempts: Int = 60
  ) {
    self.transport = transport
    self.pollInterval = pollInterval
    self.pollAttempts = pollAttempts
  }

  func isConnected(_ grant: IntegrationGrant) -> Bool? { connected[grant] }

  /// Read every row at once. Both keys are always asked for together because
  /// they answer from one grant: reading only the row the user touched is how
  /// the other row goes stale after a disconnect.
  func load() async {
    isLoading = true
    defer { isLoading = false }

    let transport = self.transport
    let results = await withTaskGroup(of: (IntegrationGrant, Bool?).self) { group in
      for grant in IntegrationGrant.allCases {
        group.addTask {
          (grant, try? await transport.connected(grant.appKey))
        }
      }
      var collected: [IntegrationGrant: Bool] = [:]
      for await (grant, value) in group {
        if let value { collected[grant] = value }
      }
      return collected
    }

    connected = results
    // Booleans only. Which grants a user holds is the whole diagnostic; the
    // grant itself never goes near a log line.
    let summary = IntegrationGrant.allCases
      .map { "\($0.appKey)=\(results[$0].map { $0 ? "connected" : "no" } ?? "unreadable")" }
      .joined(separator: " ")
    log("IntegrationGrants: read \(summary)")
  }

  /// Open the grant's authorization page, then wait for the backend to report
  /// the row connected.
  ///
  /// The OAuth callback lands on the backend, not on this app, so there is no
  /// deep link to wait on. Polling is how the desktop learns the browser half
  /// finished; the mobile app gets the same signal by reloading when the user
  /// comes back to it.
  func connect(_ grant: IntegrationGrant) async {
    guard busy == nil else { return }
    busy = grant
    errorMessage = nil
    defer { busy = nil }

    do {
      let url = try await transport.oauthURL(grant.appKey)
      guard await transport.openInBrowser(url) else {
        throw IntegrationGrantError.browserRefused
      }

      for _ in 0..<pollAttempts {
        try? await Task.sleep(for: pollInterval)
        if Task.isCancelled { return }
        if (try? await transport.connected(grant.appKey)) == true {
          await load()
          return
        }
      }

      // Not a failure of the grant, only of our patience. Re-read in case the
      // approval landed between the last poll and now.
      await load()
      if connected[grant] != true {
        errorMessage =
          "Didn't hear back from Google. If you approved access, reopen Settings to check."
      }
    } catch {
      errorMessage = UserFacingErrorPresentation.message(
        for: error, while: .integration(grant.displayName))
    }
  }

  /// Drop the grant, then re-read every row: Gmail and Google Calendar share
  /// one grant, so disconnecting either also disconnects the other.
  func disconnect(_ grant: IntegrationGrant) async {
    guard busy == nil else { return }
    busy = grant
    errorMessage = nil
    defer { busy = nil }

    do {
      try await transport.disconnect(grant.appKey)
      await load()
    } catch {
      errorMessage = UserFacingErrorPresentation.message(
        for: error, while: .integration(grant.displayName))
    }
  }
}
