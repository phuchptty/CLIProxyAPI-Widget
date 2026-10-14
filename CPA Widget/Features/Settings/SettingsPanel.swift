import SwiftUI

struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(AtollIntegration.self) private var atoll
    let close: () -> Void
    @State private var instanceURL = ""
    @State private var key = ""
    @State private var localError: String?
    @State private var isTesting = false
    @State private var didTest = false
    @State private var showHTTPWarning = false
    @State private var pendingHTTPAction: PendingHTTPAction?

    private enum PendingHTTPAction {
        case testConnection(url: String, key: String)
        case save(url: String, key: String)
    }
    var body: some View {
        @Bindable var model = model
        @Bindable var atoll = atoll
        VStack(alignment: .leading, spacing: 16) {
            Label("CPA Widget", systemImage: "server.rack")
                .font(.title2.bold())
            Text("CLI Proxy API · Management v8")
                .foregroundStyle(.secondary)
            Form {
                Section("Instance") {
                    TextField("Instance URL", text: $instanceURL)
                        .autocorrectionDisabled()
                    SecureField("Management key", text: $key)
                    Text("Use the management key, not a client API key. The key is stored in macOS Keychain. HTTP does not encrypt the key or traffic; HTTP outside loopback and 100.x.x.x requires confirmation.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Test Connection", action: { begin(.testConnection(url: instanceURL, key: key)) })
                            .disabled(isTesting || model.isRefreshing)
                        if isTesting { ProgressView().controlSize(.small) }
                    }
                }
                Section("Menu bar") {
                    Toggle("Enable status widget", isOn: $model.widgetEnabled)
                    Text("When disabled, reopen CPA Widget from Finder to access Settings and re-enable the icon.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Atoll") {
                    Toggle("Show quotas in Atoll", isOn: Binding(get: { atoll.enabled }, set: { atoll.setEnabled($0) }))
                    Text(atoll.statusMessage).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Connect / Show in Atoll", action: atoll.beginConnect)
                            .disabled(atoll.isConnecting || !atoll.enabled)
                        Button("Open Atoll", action: atoll.openAtoll)
                    }
                    Picker("Compact summary", selection: Binding(get: { atoll.summarySelection }, set: { atoll.selectSummary($0) })) {
                        Text("Automatic").tag(Optional<AtollSummarySelection>.none)
                        ForEach(atoll.summaryOptions) { entry in Text(entry.label).tag(Optional(entry.selection)) }
                    }
                    Text("Background refresh continues while Atoll is enabled. Account labels are shared with Atoll. Enable Extensions, notch experiences/tabs, live activities, and Allow interactive web content in Atoll Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Provider metrics") {
                    Text("Enabled accounts are listed per provider. Quotas come from an instance quota plugin, or from the built-in Codex and Antigravity probe. A provider with neither stays unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let message = localError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            } else if didTest {
                Label("Connection successful", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: { begin(.save(url: instanceURL, key: key)) })
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || model.isRefreshing)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        // Minimum, not fixed: the window's safe-area insets would otherwise shrink a fixed frame
        // and clip the form.
        .frame(minWidth: 520, minHeight: 660)
        .onAppear(perform: load)
        .onChange(of: instanceURL) { clearTestResult() }
        .onChange(of: key) { clearTestResult() }
        .confirmationDialog("Use an insecure HTTP connection?", isPresented: $showHTTPWarning, titleVisibility: .visible) {
            Button("Continue over HTTP", role: .destructive) {
                guard let action = pendingHTTPAction else { return }
                pendingHTTPAction = nil
                perform(action)
            }
            Button("Cancel", role: .cancel) { pendingHTTPAction = nil }
        } message: {
            Text("HTTP does not encrypt your management key or traffic. Anyone able to observe the network may read or modify it. Continue only on a trusted network.")
        }
    }

    private func begin(_ action: PendingHTTPAction) {
        let endpoint = instanceURL
        let managementKey = key
        let capturedAction: PendingHTTPAction
        switch action {
        case .testConnection(_, _): capturedAction = .testConnection(url: endpoint, key: managementKey)
        case .save(_, _): capturedAction = .save(url: endpoint, key: managementKey)
        }
        do {
            if try ManagementClient.requiresHTTPConfirmation(for: endpoint) {
                pendingHTTPAction = capturedAction
                showHTTPWarning = true
                return
            }
            perform(capturedAction)
        } catch {
            localError = error.localizedDescription
        }
    }

    private func perform(_ action: PendingHTTPAction) {
        switch action {
        case .testConnection(let url, let key): testConnection(url: url, key: key)
        case .save(let url, let key): save(url: url, key: key)
        }
    }
    private func clearTestResult() {
        didTest = false
        localError = nil
    }



    private func testConnection(url testedURL: String, key testedKey: String) {
        localError = nil
        didTest = false
        isTesting = true
        Task {
            do {
                try await model.testConnection(instanceURL: testedURL, key: testedKey)
                if instanceURL == testedURL, key == testedKey { didTest = true }
            } catch {
                if instanceURL == testedURL, key == testedKey { localError = error.localizedDescription }
            }
            isTesting = false
        }
    }

    private func save(url: String, key: String) {
        localError = nil
        didTest = false
        do { try model.saveSettings(instanceURL: url, key: key) }
        catch { localError = error.localizedDescription }
    }

    private func load() {
        instanceURL = model.instanceURL
        do { key = try model.loadKey() }
        catch { localError = error.localizedDescription }
    }

}
