import SwiftUI

/// Circular quota chart. The ring fills with the *remaining* quota and repeats the reading in its
/// centre, so a small red ring always means a nearly exhausted window.
struct QuotaRing: View {
    let remainingFraction: Double

    /// Red below 30% left, orange below 70%, green otherwise.
    private var tint: Color {
        if remainingFraction < 0.3 { return .red }
        if remainingFraction < 0.7 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, remainingFraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(remainingFraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(3)
        }
        .frame(width: 40, height: 40)
    }
}
