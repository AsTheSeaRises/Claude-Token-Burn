import Foundation

protocol UsageServiceProtocol {
    func fetchUsage() async throws -> ProviderUsageData
}
