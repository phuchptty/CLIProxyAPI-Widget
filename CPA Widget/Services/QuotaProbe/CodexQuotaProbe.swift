import Foundation

/// Reads Codex quota from the provider's own usage endpoint through the instance's api-call
/// proxy. The URL, request headers, and window fields mirror the CLIProxyAPI Management Center
/// probe so the widget shows the same numbers when no quota plugin is installed.
struct CodexQuotaProbe: ProviderQuotaProbe {
    private static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    private static let userAgent = "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal"

    func quota(for credential: Credential, using client: ManagementClient) async throws -> QuotaResponse {
        guard let authIndex = credential.authIndex, !authIndex.isEmpty else {
            throw ManagementError.unsupportedQuota
        }
        guard let accountID = credential.chatgptAccountID, !accountID.isEmpty else {
            throw ManagementError.providerMetadata("ChatGPT account id")
        }
        let result = try await client.apiCall(
            authIndex: authIndex,
            method: "GET",
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json",
                "User-Agent": Self.userAgent,
                "Chatgpt-Account-Id": accountID
            ],
            body: nil
        )
        guard (200..<300).contains(result.statusCode) else {
            throw ManagementError.providerHTTP(result.statusCode)
        }
        guard let data = result.body?.data(using: .utf8),
              let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
            throw ManagementError.providerResponse("unreadable body")
        }
        // Primary is the five-hour window; secondary is the weekly window.
        let windows = [("5h", usage.rateLimit?.primaryWindow), ("Weekly", usage.rateLimit?.secondaryWindow)]
        let buckets = windows.compactMap { window, limits -> QuotaBucket? in
            guard let used = limits?.usedPercent, used.isFinite else { return nil }
            return QuotaBucket(
                window: window,
                remainingFraction: min(1, max(0, 1 - used / 100)),
                resetTime: Self.resetTime(after: limits?.resetAfterSeconds),
                description: nil
            )
        }
        guard !buckets.isEmpty else { throw ManagementError.providerResponse("no quota windows") }
        let plan = usage.planType ?? credential.idToken?.planType
        return QuotaResponse(
            groups: [QuotaGroup(displayName: "Usage limits", buckets: buckets)],
            summary: nil,
            subscription: plan.map { QuotaSubscription(plan: $0, tierName: nil) }
        )
    }

    /// Codex reports time until reset, so the absolute timestamp is computed locally.
    private static func resetTime(after seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return ISO8601DateFormatter().string(from: Date().addingTimeInterval(seconds))
    }
}
