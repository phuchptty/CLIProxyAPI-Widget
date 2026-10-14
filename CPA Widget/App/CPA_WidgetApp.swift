import SwiftUI

@main
struct CPA_WidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
