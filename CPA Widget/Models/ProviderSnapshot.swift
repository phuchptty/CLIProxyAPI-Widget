import Foundation

struct ProviderSnapshot: Identifiable {
    let id: String
    let accounts: [AccountSnapshot]
}
