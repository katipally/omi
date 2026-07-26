import Foundation

/// Backend transport for the shared integration grants behind Settings →
/// Integrations.
///
/// The backend derives Gmail from the Google Calendar grant, so every verb here
/// takes the integration's own app key and lets the server resolve which grant
/// actually backs it.
extension APIClient {
  func integrationConnected(appKey: String) async throws -> Bool {
    let response: IntegrationStatusResponse = try await get("v1/integrations/\(appKey)")
    return response.connected
  }

  func integrationOAuthURL(appKey: String) async throws -> URL {
    let response: IntegrationOAuthURLResponse = try await get("v1/integrations/\(appKey)/oauth-url")
    guard let url = URL(string: response.authUrl) else {
      throw IntegrationGrantError.malformedOAuthURL
    }
    return url
  }

  func disconnectIntegration(appKey: String) async throws {
    try await delete("v1/integrations/\(appKey)")
  }
}

struct IntegrationStatusResponse: Decodable {
  let connected: Bool
  let appKey: String?

  enum CodingKeys: String, CodingKey {
    case connected
    case appKey = "app_key"
  }
}

struct IntegrationOAuthURLResponse: Decodable {
  let authUrl: String

  enum CodingKeys: String, CodingKey {
    case authUrl = "auth_url"
  }
}

enum IntegrationGrantError: LocalizedError {
  case malformedOAuthURL
  case browserRefused

  var errorDescription: String? {
    switch self {
    case .malformedOAuthURL:
      return "The server returned an authorization link this app could not open."
    case .browserRefused:
      return "Couldn't open the authorization page. Check your default browser, then try again."
    }
  }
}
