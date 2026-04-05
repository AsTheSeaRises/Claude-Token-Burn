import Foundation
import Combine

final class TokenBurnViewModel: ObservableObject {
    // Session (5-hour window)
    @Published var sessionUtilization: Int  = 0     // 0–100 % used
    @Published var sessionResetsAt: Date?   = nil

    // Weekly limits
    @Published var weeklyUtilization: Int   = 0
    @Published var weeklyResetsAt: Date?    = nil

    // Model breakdowns (Opus/Sonnet)
    @Published var modelBreakdowns: [ModelBreakdown] = []

    // Extra usage
    @Published var extraUsage: ExtraUsage?  = nil

    // Status
    @Published var errorMessage: String?    = nil
    @Published var lastUpdated: Date?       = nil
    @Published var isLoading: Bool          = false
    @Published var needsLogin: Bool         = false
    @Published var isLoggingIn: Bool        = false

    // Called after each refresh so AppDelegate can update the status bar text
    var onUpdate: (() -> Void)?

    private let settingsStore = SettingsStore.shared
    private var pollTimer: Timer?
    private var settingsCancellable: AnyCancellable?

    private let usageService = AnthropicUsageService.shared

    init() {
        refresh()
        startPollTimer()

        settingsCancellable = settingsStore.objectWillChange
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] in self?.restartPollTimer() }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            do {
                let data = try await usageService.fetchUsage()
                apply(data)
                errorMessage = nil
                needsLogin   = data.needsLogin
                lastUpdated  = Date()
            } catch UsageError.tokenExpired {
                errorMessage = "Session expired"
                needsLogin   = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            onUpdate?()
        }
    }

    func login() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await AuthService.shared.login()
                let data = try await usageService.fetchUsage()
                apply(data)
                errorMessage = nil
                needsLogin   = false
                lastUpdated  = Date()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoggingIn = false
            onUpdate?()
        }
    }

    // MARK: - Derived values

    var sessionPercentRemaining: Double { max(0, Double(100 - sessionUtilization)) }

    var sessionTimeRemaining: TimeInterval {
        guard let resets = sessionResetsAt else { return 0 }
        return max(0, resets.timeIntervalSinceNow)
    }

    var statusBarLabel: String {
        guard errorMessage == nil else { return "⚠️" }
        let pct = sessionUtilization
        let secs = sessionTimeRemaining
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        return String(format: "%d%% | %dh%02dm", pct, h, m)
    }

    // MARK: - Private

    private func apply(_ data: ProviderUsageData) {
        sessionUtilization = data.sessionUtilization
        sessionResetsAt    = data.sessionResetsAt
        weeklyUtilization  = data.weeklyUtilization
        weeklyResetsAt     = data.weeklyResetsAt
        modelBreakdowns    = data.modelBreakdowns
        extraUsage         = data.extraUsage

        NotificationManager.shared.checkThresholds(
            percentUsed: Double(sessionUtilization),
            estimatedTimeRemaining: sessionTimeRemaining
        )
    }

    private func startPollTimer() {
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: settingsStore.settings.pollInterval,
            repeats: true
        ) { [weak self] _ in self?.refresh() }
    }

    private func restartPollTimer() {
        pollTimer?.invalidate()
        startPollTimer()
    }

    deinit { pollTimer?.invalidate() }
}
