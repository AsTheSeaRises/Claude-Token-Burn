import Foundation

// MARK: - API Response

struct UsageResponse: Codable {
    let fiveHour:       UsageWindow?
    let sevenDay:       UsageWindow?
    let sevenDayOpus:   UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage:     ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour       = "five_hour"
        case sevenDay       = "seven_day"
        case sevenDayOpus   = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage     = "extra_usage"
    }
}

struct UsageWindow: Codable {
    let utilization: Int        // 0–100
    let resetsAt:    String?    // ISO 8601

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let str = resetsAt else { return nil }
        // Try with fractional seconds first (e.g. "2026-04-04T20:59:59.830244+00:00")
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: str) { return d }
        // Fallback: without fractional seconds
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: str)
    }
}

struct ExtraUsage: Codable {
    let isEnabled:    Bool?
    let monthlyLimit: Int?
    let usedCredits:  Int?
    let currency:     String?

    enum CodingKeys: String, CodingKey {
        case isEnabled    = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits  = "used_credits"
        case currency
    }
}

// MARK: - Keychain Models

struct KeychainData: Codable {
    var claudeAiOauth: OAuthCredentials?
    // mcpOAuth and other keys are ignored
}

struct OAuthCredentials: Codable {
    let accessToken:      String
    let refreshToken:     String
    let expiresAt:        Int64      // milliseconds since epoch
    let scopes:           [String]?
    let subscriptionType: String?
    let rateLimitTier:    String?
}

// MARK: - Token Refresh Response

struct TokenRefreshResponse: Codable {
    let accessToken:  String
    let refreshToken: String?
    let expiresIn:    Int?      // seconds

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case keychainReadFailed(OSStatus)
    case noOAuthCredentials
    case invalidResponse
    case httpError(Int)
    case tokenExpired
    case googleAuthRequired
    case googleAuthFailed
    case cloudCodeApiError(Int)

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed:
            return "Could not read credentials — make sure Claude Code is installed"
        case .noOAuthCredentials:
            return "No Claude login found — run 'claude auth login' in Terminal"
        case .invalidResponse:
            return "Unexpected response from API"
        case .httpError(let code):
            return "API error (HTTP \(code))"
        case .tokenExpired:
            return "Session expired — open Claude Code to refresh, then click Refresh Now"
        case .googleAuthRequired:
            return "Not logged in to Google — click Login to authenticate"
        case .googleAuthFailed:
            return "Google authentication failed — please try again"
        case .cloudCodeApiError(let code):
            return "Google Cloud Code API error (HTTP \(code))"
        }
    }
}
