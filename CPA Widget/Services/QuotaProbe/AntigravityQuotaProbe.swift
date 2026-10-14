import Foundation

/// Reads Antigravity model quota through the instance's api-call proxy. The endpoint order and
/// the per-model `quotaInfo` fields mirror the CLIProxyAPI Management Center probe.
struct AntigravityQuotaProbe: ProviderQuotaProbe {
    private static let endpoints = [
        "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
        "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
        "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    ]
    private static let userAgent = "antigravity/1.11.5 windows/amd64"

    /// Models sharing one reading collapse into a single bucket; the provider has no stable
    /// family list to group by, so identical limits are the grouping key.
    private struct Signature: Hashable {
        let fraction: Double
        let reset: String?
    }

    func quota(for credential: Credential, using client: ManagementClient) async throws -> QuotaResponse {
        guard let authIndex = credential.authIndex, !authIndex.isEmpty else {
            throw ManagementError.unsupportedQuota
        }
        guard let projectID = credential.projectID, !projectID.isEmpty else {
            throw ManagementError.providerMetadata("project id")
        }
        let payload = try JSONSerialization.data(withJSONObject: ["project": projectID])
        var lastError = ManagementError.providerResponse("no quota windows")
        for endpoint in Self.endpoints {
            let result = try await client.apiCall(
                authIndex: authIndex,
                method: "POST",
                url: endpoint,
                headers: [
                    "Authorization": "Bearer $TOKEN$",
                    "Content-Type": "application/json",
                    "User-Agent": Self.userAgent
                ],
                body: String(decoding: payload, as: UTF8.self)
            )
            if result.statusCode == 401 || result.statusCode == 403 {
                // Every endpoint shares the credential, so a rejection ends the probe.
                throw ManagementError.providerHTTP(result.statusCode)
            }
            guard (200..<300).contains(result.statusCode) else {
                lastError = ManagementError.providerHTTP(result.statusCode)
                continue
            }
            guard let data = result.body?.data(using: .utf8),
                  let response = try? JSONDecoder().decode(AntigravityModelsResponse.self, from: data),
                  let models = response.models, !models.isEmpty else {
                lastError = ManagementError.providerResponse("unreadable models")
                continue
            }
            if let quota = Self.quota(from: models) { return quota }
            lastError = ManagementError.providerResponse("no quota windows")
        }
        throw lastError
    }

    private static func quota(from models: [String: AntigravityModelsResponse.Model]) -> QuotaResponse? {
        var grouped: [Signature: [String]] = [:]
        for (modelID, model) in models {
            guard let fraction = model.limits.fraction, fraction.isFinite else { continue }
            let signature = Signature(fraction: min(1, max(0, fraction)), reset: model.limits.reset)
            grouped[signature, default: []].append(modelID)
        }
        guard !grouped.isEmpty else { return nil }
        // Tightest window first so the most constrained limit is visible without scrolling.
        let buckets = grouped
            .sorted { $0.key.fraction < $1.key.fraction }
            .map { signature, modelIDs -> QuotaBucket in
                let names = modelIDs.sorted()
                // A single model already names the window, so listing it again would repeat it.
                return QuotaBucket(
                    window: names.count == 1 ? names[0] : "\(names.count) models",
                    remainingFraction: signature.fraction,
                    resetTime: signature.reset,
                    description: names.count == 1 ? nil : names.joined(separator: ", ")
                )
            }
        return QuotaResponse(
            groups: [QuotaGroup(displayName: "Model limits", buckets: buckets)],
            summary: nil,
            subscription: nil
        )
    }
}
