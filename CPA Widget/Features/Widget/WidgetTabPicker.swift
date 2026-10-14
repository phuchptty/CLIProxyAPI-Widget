import AppKit
import SwiftUI

/// The panel's tab bar.
///
/// A SwiftUI segmented `Picker` keeps its intrinsic width on macOS — neither `maxWidth: .infinity`
/// nor an explicit frame stretches it — so the bar would sit in the middle of the row instead of
/// spanning it. This bridges the same `NSSegmentedControl` with equal-width segments, which fills
/// the row while keeping the system control's appearance and accessibility.
struct WidgetTabPicker: NSViewRepresentable {
    @Binding var selection: WidgetTab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: WidgetTab.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.select(_:))
        )
        control.segmentDistribution = .fillEqually
        control.selectedSegment = index(of: selection)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let selected = index(of: selection)
        if control.selectedSegment != selected { control.selectedSegment = selected }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    private func index(of tab: WidgetTab) -> Int { WidgetTab.allCases.firstIndex(of: tab) ?? 0 }

    final class Coordinator: NSObject {
        private let selection: Binding<WidgetTab>

        init(selection: Binding<WidgetTab>) {
            self.selection = selection
        }

        @objc func select(_ sender: NSSegmentedControl) {
            guard WidgetTab.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = WidgetTab.allCases[sender.selectedSegment]
        }
    }
}
