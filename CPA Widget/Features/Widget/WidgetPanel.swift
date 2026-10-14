import SwiftUI

struct WidgetPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRefreshCoordinator.self) private var refreshCoordinator
    let showSettings: () -> Void
    let panelHeight: CGFloat

    private static let accountColumns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    private var statusTitle: String {
        if model.errorMessage != nil { return "Snapshot is stale" }
        return model.lastUpdated == nil ? "Awaiting connection" : "Connected"
    }

    private var statusIsHealthy: Bool { model.errorMessage == nil && model.lastUpdated != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("CLI Proxy API", systemImage: "server.rack")
                    .font(.headline)
                    .lineLimit(1)
                StatusChip(title: statusTitle, isHealthy: statusIsHealthy)
                Spacer(minLength: 8)
                if model.isRefreshing { ProgressView().controlSize(.small) }
                if let date = model.lastUpdated {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Last successful refresh: \(date.formatted())")
                }
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly).disabled(model.isRefreshing)
                    .help("Refresh all provider quotas")
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.providers.isEmpty {
                        ContentUnavailableView("No provider data", systemImage: "network", description: Text("Configure an instance in Settings. Connected instances with no credentials have no providers to display."))
                    }
                    ForEach(model.providers) { provider in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(provider.id.capitalized).font(.headline)
                                Spacer()
                                Text("\(provider.accounts.count) accounts").font(.caption).foregroundStyle(.secondary)
                            }
                            // Categories stay stacked; accounts pair up two per row.
                            LazyVGrid(columns: Self.accountColumns, alignment: .leading, spacing: 10) {
                                ForEach(provider.accounts) { account in
                                    AccountCard(account: account)
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Button("Settings…", systemImage: "gearshape", action: { showSettings() })
                Spacer()
                Button("Quit", action: quit)
            }
            .buttonStyle(.borderless)
        }
        .padding(18)
        .frame(width: 410, height: panelHeight)
        .onAppear { refreshCoordinator.setActive(.panel, true) }
        .onDisappear { refreshCoordinator.setActive(.panel, false) }
    }

    private func refresh() { Task { await model.refresh() } }
    private func quit() { NSApplication.shared.terminate(nil) }
}
