import Foundation

/// Reads quota for a provider the instance exposes without a quota plugin, by asking the instance
/// to forward one request to that provider with the credential's own access token.
protocol ProviderQuotaProbe: Sendable {
    func quota(for credential: Credential, using client: ManagementClient) async throws -> QuotaResponse
}
