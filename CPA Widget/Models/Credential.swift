import Foundation

struct Credential: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
    let provider: String
    let status: String?
    let disabled: Bool?
    let unavailable: Bool?
    let authIndex: String?
    let quotaPluginID: String?
    let projectID: String?
    let idToken: CodexIDTokenClaims?
    let priority: Int?
    let weight: Int?
    let success: Int?
    let failed: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, provider, status, disabled, unavailable, success, failed, priority, weight
        case authIndex = "auth_index"
        case quotaPluginID = "quota_plugin_id"
        case projectID = "project_id"
        case idToken = "id_token"
    }

    /// The instance omits `disabled` for an active credential.
    var isEnabled: Bool { disabled != true }

    /// Sorting keys mirror the instance's own scheduler: a higher priority tier is used first,
    /// and within one tier a higher weight carries a larger share of traffic. The instance
    /// defaults an absent priority to 0 and an absent weight to 1.
    var routingPriority: Int { priority ?? 0 }
    var routingWeight: Int { weight ?? 1 }

    /// True when the instance published a quota plugin for this credential's provider.
    var hasPluginQuota: Bool {
        !(quotaPluginID ?? "").isEmpty && hasAuthIndex
    }

    /// `auth_index` selects the credential for both plugin quota and provider probes.
    var hasAuthIndex: Bool {
        !(authIndex ?? "").isEmpty
    }

    var chatgptAccountID: String? { idToken?.chatgptAccountID }
}
