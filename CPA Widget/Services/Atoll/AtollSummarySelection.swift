import Foundation

struct AtollSummarySelection: Codable, Hashable, Identifiable {
    let provider: String
    let accountID: String
    let groupIndex: Int
    let bucketIndex: Int

    var id: String { "\(provider)/\(accountID)/\(groupIndex)/\(bucketIndex)" }
}
