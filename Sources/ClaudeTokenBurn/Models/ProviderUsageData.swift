import Foundation

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
