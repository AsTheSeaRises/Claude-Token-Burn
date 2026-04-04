import Foundation

struct SessionStateFile: Codable {
    let observedAtUnixSecs: Int

    enum CodingKeys: String, CodingKey {
        case observedAtUnixSecs = "observed_at_unix_secs"
    }
}

struct HistoryEntry: Codable {
    let display: String?
    let timestamp: Int64   // milliseconds since epoch
    let project: String?
    let sessionId: String?
}
