import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var instanceURL: String
    var widgetEnabled: Bool {
        didSet { defaults.set(widgetEnabled, forKey: "widgetEnabled") }
    }
    private(set) var providers: [ProviderSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private var authenticationPaused = false
    private(set) var settingsRevision = 0
    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        instanceURL = defaults.string(forKey: "instanceURL") ?? "http://localhost:8317"
        widgetEnabled = defaults.object(forKey: "widgetEnabled") as? Bool ?? true
    }

    func loadKey() throws -> String { try keychain.load() }

    func testConnection(instanceURL: String, key: String) async throws {
        let url = try ManagementClient.validatedURL(instanceURL)
        let managementKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !managementKey.isEmpty else { throw ManagementError.missingKey }
        let client = ManagementClient(baseURL: url, key: managementKey)
        _ = try await client.credentials()
    }

    func saveSettings(instanceURL: String, key: String) throws {
        let url = try ManagementClient.validatedURL(instanceURL)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManagementError.missingKey
        }
        try keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        self.instanceURL = url.absoluteString
        defaults.set(self.instanceURL, forKey: "instanceURL")
        settingsRevision += 1
        authenticationPaused = false
        providers = []
        lastUpdated = nil
        errorMessage = nil
    }

    func refresh() async {
        guard !isRefreshing, !authenticationPaused else { return }
        isRefreshing = true
        let currentRevision = settingsRevision
        defer { isRefreshing = false }
        do {
            let key = try loadKey()
            guard !key.isEmpty else {
                errorMessage = "Open Settings to enter your instance and management key."
                return
            }
            let client = ManagementClient(baseURL: try ManagementClient.validatedURL(instanceURL), key: key)
            // Disabled credentials are skipped entirely: they are neither fetched nor displayed.
            let credentials = try await client.credentials().filter(\.isEnabled)
            let indexedAccounts = try await withThrowingTaskGroup(of: (Int, AccountSnapshot).self) { group in
                var nextIndex = 0
                var results: [(Int, AccountSnapshot)] = []
                let initialCount = min(6, credentials.count)
                for index in 0..<initialCount {
                    let credential = credentials[index]
                    group.addTask { (index, try await Self.accountSnapshot(for: credential, client: client)) }
                    nextIndex += 1
                }
                while let result = try await group.next() {
                    results.append(result)
                    if nextIndex < credentials.count {
                        let index = nextIndex
                        let credential = credentials[index]
                        group.addTask { (index, try await Self.accountSnapshot(for: credential, client: client)) }
                        nextIndex += 1
                    }
                }
                // Order the way the instance routes: priority tier descending, then weight
                // descending, then the inventory's own order as a stable tie-break.
                return results.sorted { lhs, rhs in
                    let leftPriority = lhs.1.credential.routingPriority
                    let rightPriority = rhs.1.credential.routingPriority
                    if leftPriority != rightPriority { return leftPriority > rightPriority }
                    let leftWeight = lhs.1.credential.routingWeight
                    let rightWeight = rhs.1.credential.routingWeight
                    if leftWeight != rightWeight { return leftWeight > rightWeight }
                    return lhs.0 < rhs.0
                }.map(\.1)
            }
            try Task.checkCancellation()
            guard settingsRevision == currentRevision else { return }
            let grouped = Dictionary(grouping: indexedAccounts, by: { $0.credential.provider })
            providers = grouped.keys.sorted().map { ProviderSnapshot(id: $0, accounts: grouped[$0]!) }
            lastUpdated = .now
            errorMessage = nil
        } catch is CancellationError {
            // Closing the panel cancels its refresh without replacing the last snapshot.
        } catch {
            guard settingsRevision == currentRevision else { return }
            if let managementError = error as? ManagementError, managementError.stopsAuthentication {
                authenticationPaused = true
            }
            if (error as? URLError)?.code != .cancelled { errorMessage = error.localizedDescription }
        }
    }

    private static func accountSnapshot(for credential: Credential, client: ManagementClient) async throws -> AccountSnapshot {
        do {
            return AccountSnapshot(credential: credential, quota: try await quota(for: credential, client: client), errorMessage: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let managementError = error as? ManagementError, managementError.stopsAuthentication { throw error }
            return AccountSnapshot(credential: credential, quota: nil, errorMessage: error.localizedDescription)
        }
    }

    /// A published quota plugin always wins; otherwise a known provider probe reads quota through
    /// the instance. Credentials that satisfy neither stay unavailable instead of guessing.
    private static func quota(for credential: Credential, client: ManagementClient) async throws -> QuotaResponse {
        if credential.hasPluginQuota { return try await client.quota(for: credential) }
        guard credential.hasAuthIndex, let probe = QuotaProbeRegistry.probe(for: credential.provider) else {
            throw ManagementError.unsupportedQuota
        }
        return try await probe.quota(for: credential, using: client)
    }
}
