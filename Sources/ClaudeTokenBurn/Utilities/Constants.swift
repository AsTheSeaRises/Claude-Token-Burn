import Foundation
import AppKit

enum Constants {
    static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    static let statsCachePath = claudeDir.appendingPathComponent("stats-cache.json")
    static let promptCachePath = claudeDir.appendingPathComponent("cache/prompt-cache")
    static let historyPath = claudeDir.appendingPathComponent("history.jsonl")

    static func tokenColor(percentRemaining: Double) -> NSColor {
        switch percentRemaining {
        case 50...100: return .systemGreen
        case 25..<50:  return .systemYellow
        case 10..<25:  return .systemOrange
        default:       return .systemRed
        }
    }

    static func tokenColorSwiftUI(percentRemaining: Double) -> SwiftUIColor {
        switch percentRemaining {
        case 50...100: return .green
        case 25..<50:  return .yellow
        case 10..<25:  return .orange
        default:       return .red
        }
    }
}

// Alias to avoid import SwiftUI in this file
import SwiftUI
typealias SwiftUIColor = Color
