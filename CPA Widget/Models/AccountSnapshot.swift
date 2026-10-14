import Foundation

struct AccountSnapshot: Identifiable, Sendable {
    var id: String { credential.id }
    let credential: Credential
    let quota: QuotaResponse?
    let errorMessage: String?
}
