import Foundation

/// The panel's two views: quota management first, then the instance's request history.
enum WidgetTab: CaseIterable {
    case quotas
    case requests

    var title: String {
        switch self {
        case .quotas: "Quotas"
        case .requests: "Requests"
        }
    }
}
