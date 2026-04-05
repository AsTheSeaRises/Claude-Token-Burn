import Foundation

enum AuthError: LocalizedError {
    case claudeNotFound
    case loginFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code CLI not found — install from claude.ai/code"
        case .loginFailed(let code):
            return "Login failed (exit \(code)) — please try again"
        }
    }
}

final class AuthService {
    static let shared = AuthService()

    // Candidate claude binary locations
    private let claudeCandidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
        "\(NSHomeDirectory())/.npm-global/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
    ]

    // Candidate node bin dirs to prepend to PATH
    private let nodeCandidates = [
        "/opt/homebrew/opt/node@23/bin",
        "/opt/homebrew/opt/node@22/bin",
        "/opt/homebrew/opt/node@20/bin",
        "/opt/homebrew/opt/node/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    private init() {}

    /// Runs `claude auth login`, which opens the browser for OAuth.
    /// Awaits process exit (login complete or cancelled).
    func login() async throws {
        guard let claudePath = claudeCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw AuthError.claudeNotFound
        }

        // Build a PATH that includes a node installation
        var pathComponents = nodeCandidates.filter {
            FileManager.default.fileExists(atPath: $0)
        }
        pathComponents.append(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        let enrichedPath = pathComponents.joined(separator: ":")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments    = ["auth", "login"]
        process.environment  = ProcessInfo.processInfo.environment
            .merging(["PATH": enrichedPath]) { _, new in new }

        try process.run()

        // Wait for the process to finish (user completes or dismisses browser)
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        guard process.terminationStatus == 0 else {
            throw AuthError.loginFailed(process.terminationStatus)
        }
    }
}
