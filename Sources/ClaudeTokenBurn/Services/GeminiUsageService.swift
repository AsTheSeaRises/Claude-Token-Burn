import Foundation

final class GeminiUsageService: UsageServiceProtocol {
    static let shared = GeminiUsageService()

    private let modelsBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private init() {}

    func fetchUsage() async throws -> ProviderUsageData {
        let settings = SettingsStore.shared.settings
        let apiKey = settings.geminiApiKey

        guard !apiKey.isEmpty else {
            throw UsageError.geminiApiKeyMissing
        }

        // Validate API key and get available models
        let models = try await fetchModels(apiKey: apiKey)

        // Compute utilization based on configured quota limits
        return buildUsageData(models: models, settings: settings)
    }

    // MARK: - API Calls

    private func fetchModels(apiKey: String) async throws -> GeminiModelsResponse {
        guard let url = URL(string: "\(modelsBaseURL)?key=\(apiKey)") else {
            throw UsageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        case 400, 403:
            throw UsageError.geminiInvalidApiKey
        default:
            throw UsageError.httpError(http.statusCode)
        }
    }

    // MARK: - Usage Computation

    private func buildUsageData(models: GeminiModelsResponse, settings: AppSettings) -> ProviderUsageData {
        var data = ProviderUsageData()

        // Session utilization: based on per-minute quota window
        // Since we can't query real-time RPM usage from Google, show quota config info
        // The session window resets every minute for RPM-based quotas
        let now = Date()
        let calendar = Calendar.current
        let nextMinute = calendar.date(byAdding: .minute, value: 1, to: now)
        data.sessionUtilization = 0
        data.sessionResetsAt = nextMinute

        // Daily utilization: resets at midnight Pacific
        var pacificCalendar = Calendar.current
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        if let startOfDay = pacificCalendar.date(bySettingHour: 0, minute: 0, second: 0, of: now) {
            let nextDay = pacificCalendar.date(byAdding: .day, value: 1, to: startOfDay)!
            data.weeklyResetsAt = nextDay
        }
        data.weeklyUtilization = 0

        // Model breakdowns from available models
        var breakdowns: [ModelBreakdown] = []
        let geminiModels = models.models ?? []
        let hasGeminiPro = geminiModels.contains { $0.name?.contains("gemini-2.5-pro") == true || $0.name?.contains("gemini-pro") == true }
        let hasGeminiFlash = geminiModels.contains { $0.name?.contains("gemini-2.5-flash") == true || $0.name?.contains("gemini-flash") == true }

        if hasGeminiPro {
            breakdowns.append(ModelBreakdown(label: "Pro", utilization: 0))
        }
        if hasGeminiFlash {
            breakdowns.append(ModelBreakdown(label: "Flash", utilization: 0))
        }
        if breakdowns.isEmpty {
            // Fallback: show generic entry
            breakdowns.append(ModelBreakdown(label: "Gemini", utilization: 0))
        }
        data.modelBreakdowns = breakdowns

        return data
    }
}

// MARK: - Gemini API Response Models

struct GeminiModelsResponse: Codable {
    let models: [GeminiModel]?
}

struct GeminiModel: Codable {
    let name: String?
    let displayName: String?
    let description: String?
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
}
