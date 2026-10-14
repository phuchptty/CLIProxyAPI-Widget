import SwiftUI

struct StatusChip: View {
    let title: String
    let isHealthy: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isHealthy ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.quaternary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
