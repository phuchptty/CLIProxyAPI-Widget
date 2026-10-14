import Foundation

/// Selects the provider probe that can read quota when the instance published no quota plugin.
enum QuotaProbeRegistry {
    private static let probes: [String: any ProviderQuotaProbe] = [
        "codex": CodexQuotaProbe(),
        "antigravity": AntigravityQuotaProbe()
    ]

    static func probe(for provider: String) -> (any ProviderQuotaProbe)? {
        probes[provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}
