import Foundation

final class GeminiUsageService: UsageServiceProtocol {
    static let shared = GeminiUsageService()

    private let cloudCodeBaseURL = "https://cloudcode-pa.googleapis.com"

    private init() {}

    func fetchUsage() async throws -> ProviderUsageData {
        let token = try await GoogleAuthService.shared.getValidAccessToken()

        // Fetch quota data from Cloud Code API
        let assistResponse = try await loadCodeAssist(token: token)

        // Cache the project ID if we got one
        if let projectId = assistResponse.projectId {
            GoogleAuthService.shared.updateProjectId(projectId)
        }

        // Optionally fetch available models for richer data
        let modelsResponse = try? await fetchAvailableModels(token: token)

        return buildUsageData(assist: assistResponse, models: modelsResponse)
    }

    // MARK: - Cloud Code API Calls

    private func loadCodeAssist(token: String) async throws -> CloudCodeAssistResponse {
        let url = URL(string: "\(cloudCodeBaseURL)/v1internal:loadCodeAssist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "metadata": [
                "ideType": "MACOS_APP",
                "platform": "darwin",
                "pluginType": "PLUGIN_TYPE_UNSPECIFIED",
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(CloudCodeAssistResponse.self, from: data)
        case 401, 403:
            throw UsageError.googleAuthRequired
        default:
            throw UsageError.cloudCodeApiError(http.statusCode)
        }
    }

    private func fetchAvailableModels(token: String) async throws -> CloudCodeModelsResponse {
        let url = URL(string: "\(cloudCodeBaseURL)/v1internal:fetchAvailableModels")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageError.invalidResponse
        }

        return try JSONDecoder().decode(CloudCodeModelsResponse.self, from: data)
    }

    // MARK: - Data Mapping

    private func buildUsageData(assist: CloudCodeAssistResponse, models: CloudCodeModelsResponse?) -> ProviderUsageData {
        var data = ProviderUsageData()

        // Collect all model quota entries
        var modelQuotas: [CloudCodeModelConfig] = []
        if let configs = assist.cascadeModelConfigData?.modelConfigs {
            modelQuotas = configs.filter { $0.quotaInfo != nil && shouldShowModel($0) }
        }

        // If the assist response didn't have model configs, try the models response
        if modelQuotas.isEmpty, let availableModels = models?.models {
            modelQuotas = availableModels.map { m in
                CloudCodeModelConfig(modelId: m.modelId, displayLabel: m.displayLabel, quotaInfo: m.quotaInfo)
            }.filter { $0.quotaInfo != nil && shouldShowModel($0) }
        }

        // Session utilization: use the most-consumed model's utilization
        // (utilization = 100 - remainingPercent)
        var highestUtilization = 0
        var soonestReset: Date?

        var breakdowns: [ModelBreakdown] = []
        for model in modelQuotas {
            let remaining = model.quotaInfo?.remainingPercent ?? 100
            let utilization = max(0, 100 - remaining)
            let label = cleanModelLabel(model.displayLabel ?? model.modelId ?? "Unknown")

            breakdowns.append(ModelBreakdown(label: label, utilization: utilization))

            if utilization > highestUtilization {
                highestUtilization = utilization
            }
            if let resetDate = model.quotaInfo?.resetDate {
                if soonestReset == nil || resetDate < soonestReset! {
                    soonestReset = resetDate
                }
            }
        }

        // Sort breakdowns alphabetically
        breakdowns.sort { $0.label < $1.label }

        data.sessionUtilization = highestUtilization
        data.sessionResetsAt = soonestReset
        data.modelBreakdowns = breakdowns

        // Weekly/credits utilization
        if let credits = assist.promptCredits {
            data.weeklyUtilization = credits.usedPercent
            // Credits typically reset monthly — no reset date from API, so leave nil
            data.weeklyResetsAt = nil

            // Map to ExtraUsage for display
            data.extraUsage = ExtraUsage(
                isEnabled: true,
                monthlyLimit: credits.monthlyLimit,
                usedCredits: credits.used ?? ((credits.monthlyLimit ?? 0) - (credits.available ?? 0)),
                currency: nil
            )
        }

        return data
    }

    private func shouldShowModel(_ model: CloudCodeModelConfig) -> Bool {
        let id = model.modelId?.lowercased() ?? ""
        // Filter out internal/non-user-facing models
        if id.hasPrefix("chat_") || id.hasPrefix("tab_") || id.hasPrefix("rev") { return false }
        if id.contains("imagen") || id.contains("lite") { return false }
        return true
    }

    private func cleanModelLabel(_ label: String) -> String {
        // Simplify labels like "Gemini 2.5 Pro" → "2.5 Pro"
        var cleaned = label
        if cleaned.lowercased().hasPrefix("gemini ") {
            cleaned = String(cleaned.dropFirst(7))
        }
        return cleaned
    }
}
