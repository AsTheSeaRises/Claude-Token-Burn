import Foundation

enum UsageProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "flame.fill"
        case .gemini: return "sparkles"
        }
    }

    var loginActionLabel: String {
        switch self {
        case .claude: return "Login to Claude"
        case .gemini: return "Login to Google"
        }
    }
}

struct ModelBreakdown: Identifiable {
    let label: String
    let utilization: Int
    var id: String { label }
}

struct ProviderUsageData {
    var sessionUtilization: Int = 0
    var sessionResetsAt: Date?

    var weeklyUtilization: Int = 0
    var weeklyResetsAt: Date?

    var modelBreakdowns: [ModelBreakdown] = []

    var extraUsage: ExtraUsage?

    var needsLogin: Bool = false
}
