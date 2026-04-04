import Foundation

struct StatsCache: Codable {
    let version: Int?
    let lastComputedDate: String?
    let dailyModelTokens: [DailyModelTokens]?
    let modelUsage: [String: ModelUsage]?
    let dailyActivity: [DailyActivity]?
    let totalSessions: Int?
    let totalMessages: Int?
}

// tokensByModel maps model name -> total tokens (single Int, not broken down)
struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
}

struct ModelUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let costUSD: Double?
}

struct DailyActivity: Codable {
    let date: String
    let messageCount: Int?
    let sessionCount: Int?
    let toolCallCount: Int?
}
