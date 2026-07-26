import XCTest

@testable import Omi_Computer

/// Gmail has no OAuth grant of its own: it rides the Google Calendar grant and
/// reads connected only when that grant actually carries the Gmail scope. Every
/// case here is one consequence of that sharing, which is exactly what a
/// per-row model gets wrong.
@MainActor
final class IntegrationGrantStoreTests: XCTestCase {

  /// Stands in for the backend's `DERIVED_INTEGRATIONS` routing: one Google
  /// grant, two rows reading from it.
  private actor FakeGoogleGrant {
    private(set) var hasGrant: Bool
    private(set) var hasGmailScope: Bool
    private(set) var browserOpens = 0
    private(set) var disconnectedKeys: [String] = []

    init(hasGrant: Bool, hasGmailScope: Bool) {
      self.hasGrant = hasGrant
      self.hasGmailScope = hasGmailScope
    }

    func connected(_ appKey: String) -> Bool {
      switch appKey {
      case "google_calendar": return hasGrant
      case "gmail": return hasGrant && hasGmailScope
      default: return false
      }
    }

    /// Approving in the browser re-grants Google with the current scope set,
    /// which now includes `gmail.readonly`.
    func approveInBrowser() {
      browserOpens += 1
      hasGrant = true
      hasGmailScope = true
    }

    /// Deleting either row drops the shared grant.
    func disconnect(_ appKey: String) {
      disconnectedKeys.append(appKey)
      hasGrant = false
      hasGmailScope = false
    }

    func openCount() -> Int { browserOpens }
    func deletedKeys() -> [String] { disconnectedKeys }
  }

  private func makeStore(hasGrant: Bool, hasGmailScope: Bool) -> (
    IntegrationGrantStore, FakeGoogleGrant
  ) {
    let backend = FakeGoogleGrant(hasGrant: hasGrant, hasGmailScope: hasGmailScope)
    let transport = IntegrationGrantTransport(
      connected: { await backend.connected($0) },
      oauthURL: { _ in URL(string: "https://accounts.google.com/o/oauth2/v2/auth")! },
      disconnect: { await backend.disconnect($0) },
      openInBrowser: { _ in
        await backend.approveInBrowser()
        return true
      }
    )
    let store = IntegrationGrantStore(
      transport: transport,
      pollInterval: .milliseconds(1),
      pollAttempts: 5
    )
    return (store, backend)
  }

  func testALegacyCalendarGrantReadsGmailAsNotConnected() async {
    // The exact state every pre-Gmail Calendar user is in: the grant is real
    // and Calendar keeps working, but it predates `gmail.readonly`, so Gmail
    // has to say so rather than fail later inside the chat tool.
    let (store, _) = makeStore(hasGrant: true, hasGmailScope: false)

    await store.load()

    XCTAssertEqual(store.isConnected(.googleCalendar), true)
    XCTAssertEqual(store.isConnected(.gmail), false)
  }

  func testConnectingGmailUpgradesTheSharedGrantAndRereadsBothRows() async {
    let (store, backend) = makeStore(hasGrant: true, hasGmailScope: false)
    await store.load()

    await store.connect(.gmail)

    let opens = await backend.openCount()
    XCTAssertEqual(opens, 1)
    XCTAssertEqual(store.isConnected(.gmail), true)
    XCTAssertEqual(
      store.isConnected(.googleCalendar), true,
      "Calendar must survive the Gmail reconnect - it is the same grant")
    XCTAssertNil(store.errorMessage)
  }

  func testDisconnectingGmailAlsoClearsCalendarInTheUI() async {
    // Reading back only the row the user touched is the bug this guards: the
    // backend drops one grant, so leaving Calendar showing Connected would be
    // the UI lying about a grant that no longer exists.
    let (store, backend) = makeStore(hasGrant: true, hasGmailScope: true)
    await store.load()
    XCTAssertEqual(store.isConnected(.googleCalendar), true)

    await store.disconnect(.gmail)

    let deleted = await backend.deletedKeys()
    XCTAssertEqual(deleted, ["gmail"])
    XCTAssertEqual(store.isConnected(.gmail), false)
    XCTAssertEqual(store.isConnected(.googleCalendar), false)
  }

  func testNoGrantAtAllReadsBothRowsAsNotConnected() async {
    let (store, _) = makeStore(hasGrant: false, hasGmailScope: false)

    await store.load()

    XCTAssertEqual(store.isConnected(.googleCalendar), false)
    XCTAssertEqual(store.isConnected(.gmail), false)
  }

  func testEitherRowNamesBothProductsWhenDisconnecting() {
    // Whichever row the user clicks, the confirmation has to name what actually
    // goes away.
    XCTAssertEqual(IntegrationGrant.gmail.disconnectDisplayName, "Gmail and Google Calendar")
    XCTAssertEqual(
      IntegrationGrant.googleCalendar.disconnectDisplayName, "Gmail and Google Calendar")
  }

  func testAppKeysMatchTheBackendRoutingKeys() {
    // `DERIVED_INTEGRATIONS` routes on these exact strings.
    XCTAssertEqual(IntegrationGrant.gmail.appKey, "gmail")
    XCTAssertEqual(IntegrationGrant.googleCalendar.appKey, "google_calendar")
  }

  func testASecondFlowIsRefusedWhileOneIsInFlight() async {
    // Both rows drive one grant, so a concurrent connect would race the first
    // over the same state.
    let (store, backend) = makeStore(hasGrant: false, hasGmailScope: false)

    async let first: Void = store.connect(.gmail)
    async let second: Void = store.connect(.googleCalendar)
    _ = await (first, second)

    let opens = await backend.openCount()
    XCTAssertEqual(opens, 1, "Only one authorization page may be opened at a time")
  }
}
