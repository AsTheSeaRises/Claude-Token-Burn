import Foundation

// MARK: - loadCodeAssist Response

struct CloudCodeAssistResponse: Codable {
    let projectId: String?
    let planType: String?
    let promptCredits: CloudCodePromptCredits?
    let cascadeModelConfigData: CloudCodeModelConfigData?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case planType = "plan_type"
        case promptCredits = "prompt_credits"
        case cascadeModelConfigData = "cascade_model_config_data"
    }
}

struct CloudCodePromptCredits: Codable {
    let available: Int?
    let monthlyLimit: Int?
    let used: Int?

    enum CodingKeys: String, CodingKey {
        case available
        case monthlyLimit = "monthly_limit"
        case used
    }

    var usedPercent: Int {
        guard let limit = monthlyLimit, limit > 0 else { return 0 }
        let usedCount = used ?? ((monthlyLimit ?? 0) - (available ?? 0))
        return min(100, max(0, (usedCount * 100) / limit))
    }

    var remainingPercent: Int {
        return max(0, 100 - usedPercent)
    }
}

struct CloudCodeModelConfigData: Codable {
    let modelConfigs: [CloudCodeModelConfig]?

    enum CodingKeys: String, CodingKey {
        case modelConfigs = "model_configs"
    }
}

struct CloudCodeModelConfig: Codable {
    let modelId: String?
    let displayLabel: String?
    let quotaInfo: CloudCodeQuotaInfo?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case displayLabel = "display_label"
        case quotaInfo = "quota_info"
    }
}

struct CloudCodeQuotaInfo: Codable {
    let remainingPercent: Int?
    let resetTime: String?       // ISO 8601
    let isExhausted: Bool?

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetTime = "reset_time"
        case isExhausted = "is_exhausted"
    }

    var resetDate: Date? {
        guard let str = resetTime else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: str) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: str)
    }
}

// MARK: - fetchAvailableModels Response

struct CloudCodeModelsResponse: Codable {
    let models: [CloudCodeAvailableModel]?
}

struct CloudCodeAvailableModel: Codable {
    let modelId: String?
    let displayLabel: String?
    let quotaInfo: CloudCodeQuotaInfo?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case displayLabel = "display_label"
        case quotaInfo = "quota_info"
    }
}
