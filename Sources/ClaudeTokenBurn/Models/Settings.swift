import Foundation

struct AppSettings: Codable {
    var pollInterval: Double             = 60.0
    var notificationThresholds: [Double] = [75.0, 90.0, 95.0]
    var enabledThresholds: [Bool]        = [true, true, true]
    var launchAtLogin: Bool              = false
    var showExtraUsage: Bool             = true

    // Provider selection
    var selectedProvider: String          = "claude"

    // Gemini settings (kept for backwards compat, project ID auto-populated from API)
    var geminiProjectId: String           = ""
}
