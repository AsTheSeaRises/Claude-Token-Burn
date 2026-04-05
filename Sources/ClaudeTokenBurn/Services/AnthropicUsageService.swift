import Foundation
import Security

final class AnthropicUsageService {
    static let shared = AnthropicUsageService()

    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private init() {}

    func fetchUsage() async throws -> ProviderUsageData {
        let creds = try readCredentials()

        let expiryDate = Date(timeIntervalSince1970: TimeInterval(creds.expiresAt) / 1000.0)
        if expiryDate.timeIntervalSinceNow < 0 {
            throw UsageError.tokenExpired
        }

        let response = try await callUsageAPI(token: creds.accessToken, attempt: 0)
        return mapToProviderData(response)
    }

    private func mapToProviderData(_ r: UsageResponse) -> ProviderUsageData {
        var data = ProviderUsageData()

        if let w = r.fiveHour {
            data.sessionUtilization = w.utilization
            data.sessionResetsAt = w.resetsAtDate
        }
        if let w = r.sevenDay {
            data.weeklyUtilization = w.utilization
            data.weeklyResetsAt = w.resetsAtDate
        }

        var breakdowns: [ModelBreakdown] = []
        if let opus = r.sevenDayOpus {
            breakdowns.append(ModelBreakdown(label: "Opus", utilization: opus.utilization))
        }
        if let sonnet = r.sevenDaySonnet {
            breakdowns.append(ModelBreakdown(label: "Sonnet", utilization: sonnet.utilization))
        }
        data.modelBreakdowns = breakdowns
        data.extraUsage = r.extraUsage
        return data
    }

    // MARK: - API call (with retry on transient 429)

    private func callUsageAPI(token: String, attempt: Int) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)",   forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20",  forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json",  forHTTPHeaderField: "Accept")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/1.0",   forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        case 401:
            throw UsageError.tokenExpired
        case 429 where attempt < 2:
            let delay: UInt64 = attempt == 0 ? 5_000_000_000 : 15_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callUsageAPI(token: token, attempt: attempt + 1)
        case 429:
            // Persistent 429 after retries — likely an expired/invalid token
            throw UsageError.tokenExpired
        default:
            throw UsageError.httpError(http.statusCode)
        }
    }

    // MARK: - Keychain (read-only — Claude Code manages token refresh)

    private func readCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw UsageError.keychainReadFailed(status)
        }

        let keychainData = try JSONDecoder().decode(KeychainData.self, from: data)
        guard let oauth = keychainData.claudeAiOauth else {
            throw UsageError.noOAuthCredentials
        }
        return oauth
    }
}
