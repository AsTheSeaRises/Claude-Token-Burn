import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private var firedThresholds: Set<Int> = []

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkThresholds(percentUsed: Double, estimatedTimeRemaining: TimeInterval) {
        let settings = SettingsStore.shared.settings
        for i in settings.notificationThresholds.indices {
            guard i < settings.enabledThresholds.count, settings.enabledThresholds[i] else { continue }
            let threshold = settings.notificationThresholds[i]
            let key = Int(threshold)
            guard !firedThresholds.contains(key), percentUsed >= threshold else { continue }
            firedThresholds.insert(key)
            fire(threshold: threshold, timeRemaining: estimatedTimeRemaining)
        }
    }

    func resetWindow() { firedThresholds.removeAll() }

    private func fire(threshold: Double, timeRemaining: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Token Burn"
        let pctLeft = Int(100 - threshold)
        var body = "\(Int(threshold))% of session used — \(pctLeft)% remaining."
        if timeRemaining > 0 {
            let h = Int(timeRemaining) / 3600
            let m = (Int(timeRemaining) % 3600) / 60
            body += h > 0 ? " Window resets in \(h)h \(m)m." : " Window resets in \(m)m."
        }
        content.body  = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ctb_threshold_\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
