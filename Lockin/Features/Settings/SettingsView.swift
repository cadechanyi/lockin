import SwiftUI
import SwiftData
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AppSettings.createdAt) private var settingsList: [AppSettings]
    @AppStorage(DeviceSettings.Key.screenTimeAuthorized) private var screenTimeAuthorized = false
    @AppStorage(DeviceSettings.Key.passcodeConfirmed) private var passcodeConfirmed = false
    @AppStorage(DeviceSettings.Key.openAtLogin) private var openAtLogin = false
    @State private var apiKey = ""
    @State private var xboxKey = ""
    @State private var provider: LLMProvider = .anthropic
    @State private var nudge = 15
    @State private var showOnboarding = false

    private var settings: AppSettings {
        if let existing = settingsList.first { return existing }
        let created = AppSettings()
        context.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            Form {
                SyncSection()
                Section("Grading LLM") {
                    Picker("Provider", selection: $provider) {
                        ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                    }
                    SecureField("API key", text: $apiKey)
                    Text("Stored in Keychain on this device. Used only to generate and grade digital validation questions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Xbox") {
                    SecureField("OpenXBL API key", text: $xboxKey)
                    Stepper("Nudge every \(nudge) minutes", value: $nudge, in: 5...60)
                    Text("Presence is checked during sessions. The console itself is never blocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #if os(iOS)
                Section("Screen Time") {
                    LabeledContent("Authorized", value: screenTimeAuthorized ? "Yes" : "No")
                    LabeledContent("Passcode confirmed", value: passcodeConfirmed ? "Yes" : "No")
                    Button("Re-run hard lock setup") { showOnboarding = true }
                }
                #endif
                #if os(macOS)
                Section("Mac") {
                    Toggle("Open Lockin at login", isOn: Binding(
                        get: { openAtLogin },
                        set: { newValue in
                            openAtLogin = newValue
                            setLoginItem(newValue)
                        }
                    ))
                    Text("Keep Lockin running so Mac apps stay quit during active blocks. Calendar and sessions sync with iPhone over iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Re-run Mac setup") { showOnboarding = true }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                apiKey = KeychainStore.get(KeychainStore.Key.llmAPIKey) ?? ""
                xboxKey = KeychainStore.get(KeychainStore.Key.xboxAPIKey) ?? ""
                provider = LLMProvider(rawValue: settings.llmProviderRaw) ?? .anthropic
                nudge = settings.xboxNudgeIntervalMinutes
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
        }
    }

    private func save() {
        KeychainStore.set(apiKey, for: KeychainStore.Key.llmAPIKey)
        KeychainStore.set(xboxKey, for: KeychainStore.Key.xboxAPIKey)
        settings.llmProviderRaw = provider.rawValue
        settings.xboxNudgeIntervalMinutes = nudge
        AppGroup.defaults.set(nudge, forKey: AppGroup.Key.xboxNudgeMinutes)
        try? context.save()
    }

    #if os(macOS)
    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore; toggle still stored.
        }
    }
    #endif
}

/// Live sync diagnostics. If a device is not syncing, this says why.
private struct SyncSection: View {
    @EnvironmentObject private var sync: SyncMonitor

    var body: some View {
        Section("iCloud sync") {
            switch sync.mode {
            case .cloudKit:
                LabeledContent("Storage", value: "iCloud (CloudKit)")
            case .localOnly:
                LabeledContent("Storage", value: "This device only")
                Label("Not syncing. This device opened a local database instead of iCloud.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .memoryOnly:
                LabeledContent("Storage", value: "Temporary (not saved)")
                Label("Database could not be opened. Changes will be lost when the app quits.", systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if case .localOnly(let reason) = sync.mode {
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(6)
            } else if case .memoryOnly(let reason) = sync.mode {
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(6)
            }

            LabeledContent("iCloud account", value: sync.accountStatus)
            LabeledContent("Last received", value: format(sync.lastImport))
            LabeledContent("Last sent", value: format(sync.lastExport))
            if let error = sync.lastError {
                Text("Last error: \(error)").font(.caption).foregroundStyle(.red)
            }
            Button("Re-check iCloud") { Task { await sync.refreshAccount() } }
            Text("Both devices need the same Apple ID and builds signed by the same team. Changes can take up to a minute to arrive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
