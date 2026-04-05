import Foundation
import Security

final class GoogleAuthService {
    static let shared = GoogleAuthService()

    // Google OAuth client credentials (public/installed app type — safe to distribute).
    // These are loaded from the app bundle's GoogleOAuth.plist, or fallback to env vars.
    private let clientId: String
    private let clientSecret: String
    private let scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email"]
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"
    private let keychainService = "ClaudeTokenBurn-google"

    private init() {
        // Load from GoogleOAuth.plist in the app bundle, or fall back to environment variables
        if let plistURL = Bundle.main.url(forResource: "GoogleOAuth", withExtension: "plist"),
           let plistData = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: String] {
            self.clientId = plist["CLIENT_ID"] ?? ""
            self.clientSecret = plist["CLIENT_SECRET"] ?? ""
        } else {
            // Fall back to environment variables for development
            self.clientId = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? ""
            self.clientSecret = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"] ?? ""
        }
    }

    // MARK: - Public API

    /// Returns a valid access token, refreshing if expired.
    func getValidAccessToken() async throws -> String {
        guard let tokens = loadTokens() else {
            throw UsageError.googleAuthRequired
        }

        // Check if token is still valid (with 60s buffer)
        if Date().timeIntervalSince1970 < tokens.expiresAt - 60 {
            return tokens.accessToken
        }

        // Try to refresh
        guard let refreshToken = tokens.refreshToken else {
            throw UsageError.googleAuthRequired
        }

        let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
        let newTokens = GoogleTokens(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? refreshToken,
            expiresAt: Date().timeIntervalSince1970 + Double(refreshed.expiresIn ?? 3600),
            email: tokens.email,
            projectId: tokens.projectId
        )
        saveTokens(newTokens)
        return newTokens.accessToken
    }

    /// The stored email address, if logged in.
    var currentEmail: String? {
        loadTokens()?.email
    }

    /// The stored project ID, if available.
    var currentProjectId: String? {
        loadTokens()?.projectId
    }

    /// Whether the user is authenticated (has stored tokens).
    var isAuthenticated: Bool {
        loadTokens() != nil
    }

    /// Update the stored project ID after fetching it from the API.
    func updateProjectId(_ projectId: String) {
        guard var tokens = loadTokens() else { return }
        tokens.projectId = projectId
        saveTokens(tokens)
    }

    /// Browser-based OAuth login flow.
    func login() async throws {
        let (code, redirectURI) = try await performAuthorizationCodeFlow()
        let tokenResponse = try await exchangeCodeForTokens(code: code, redirectURI: redirectURI)

        let expiresAt = Date().timeIntervalSince1970 + Double(tokenResponse.expiresIn ?? 3600)

        // Fetch user email
        let email = try await fetchUserEmail(accessToken: tokenResponse.accessToken)

        let tokens = GoogleTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiresAt,
            email: email,
            projectId: nil
        )
        saveTokens(tokens)
    }

    /// Remove stored tokens (logout).
    func logout() {
        deleteTokens()
    }

    // MARK: - Authorization Code Flow

    private func performAuthorizationCodeFlow() async throws -> (code: String, redirectURI: String) {
        // Find an available port
        let listener = try NWListenerWrapper()
        let port = listener.port
        let redirectURI = "http://127.0.0.1:\(port)"

        // Build authorization URL
        let state = UUID().uuidString
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]

        let authorizationURL = components.url!

        // Open browser
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [authorizationURL.absoluteString]
        try process.run()

        // Wait for callback
        let code = try await listener.waitForCallback(expectedState: state, timeout: 120)
        return (code, redirectURI)
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws -> GoogleOAuthTokenResponse {
        let url = URL(string: tokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageError.googleAuthFailed
        }
        return try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthTokenResponse {
        let url = URL(string: tokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageError.googleAuthRequired
        }
        return try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: data)
    }

    // MARK: - User Info

    private func fetchUserEmail(accessToken: String) async throws -> String? {
        let url = URL(string: userInfoURL)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        let info = try JSONDecoder().decode(GoogleUserInfoResponse.self, from: data)
        return info.email
    }

    // MARK: - Keychain Storage

    private func loadTokens() -> GoogleTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    private func saveTokens(_ tokens: GoogleTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        deleteTokens()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Token Models

struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: TimeInterval   // seconds since epoch
    var email: String?
    var projectId: String?
}

struct GoogleOAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case tokenType    = "token_type"
        case scope
    }
}

struct GoogleUserInfoResponse: Codable {
    let email: String?
    let name: String?
}

// MARK: - Local HTTP Listener for OAuth Callback

import Network

/// Minimal TCP listener that waits for a single OAuth redirect callback.
final class NWListenerWrapper {
    let port: UInt16
    private let listener: NWListener

    init() throws {
        // Let the system pick an available port
        let params = NWParameters.tcp
        let nwListener = try NWListener(using: params, on: .any)
        self.listener = nwListener

        // Start listener synchronously to get the assigned port
        let semaphore = DispatchSemaphore(value: 0)
        var assignedPort: UInt16 = 0
        nwListener.stateUpdateHandler = { state in
            if case .ready = state {
                assignedPort = nwListener.port?.rawValue ?? 0
                semaphore.signal()
            }
        }
        nwListener.start(queue: .global())
        semaphore.wait()
        self.port = assignedPort
    }

    func waitForCallback(expectedState: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard !resumed else { return }
                resumed = true
                self?.listener.cancel()
                continuation.resume(throwing: UsageError.googleAuthFailed)
            }

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    guard !resumed, let data = data, let request = String(data: data, encoding: .utf8) else { return }

                    // Parse the GET request for code and state
                    guard let firstLine = request.split(separator: "\r\n").first,
                          let pathPart = firstLine.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: String(pathPart)),
                          let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                          let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
                          state == expectedState else {
                        // Send error response
                        let errorHTML = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\n\r\n<html><body><h2>Authentication failed</h2><p>Please try again.</p></body></html>"
                        connection.send(content: errorHTML.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                        return
                    }

                    // Send success response
                    let successHTML = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body><h2>Authentication successful!</h2><p>You can close this window and return to Token Burn.</p></body></html>"
                    connection.send(content: successHTML.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })

                    resumed = true
                    self?.listener.cancel()
                    continuation.resume(returning: code)
                }
            }
        }
    }
}
