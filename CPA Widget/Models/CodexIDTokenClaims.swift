import Foundation

/// Claims the instance exposes for a Codex credential under the credential's `id_token` object.
struct CodexIDTokenClaims: Decodable, Sendable {
    let chatgptAccountID: String?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case chatgptAccountID = "chatgpt_account_id"
        case planType = "plan_type"
    }
}
