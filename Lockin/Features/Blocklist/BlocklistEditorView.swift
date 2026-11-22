import SwiftUI
import SwiftData
#if os(iOS)
import FamilyControls
#endif
#if os(macOS)
import AppKit
#endif

struct BlocklistEditorView: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context
    @Bindable var list: Blocklist
    @State private var customURL = ""
    #if os(iOS)
    @State private var pickerIsPresented = false
    @State private var selection = FamilyActivitySelection()
    #endif

    private var addOnly: Bool { lockState.isFrozen }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $list.name)
                    .disabled(addOnly)
            }

            #if os(iOS)
            Section {
                Button(addOnly ? "Add apps & sites (cannot remove while blocked)" : "Choose apps & sites") {
                    pickerIsPresented = true
                }
                Text("Apple’s picker is required for Screen Time shields. Select Instagram, YouTube, Apple TV, and site tokens here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .familyActivityPicker(isPresented: $pickerIsPresented, selection: $selection)
            .onChange(of: selection) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) {
                    if addOnly, let existing = list.familyActivitySelectionData,
                       let old = try? JSONDecoder().decode(FamilyActivitySelection.self, from: existing) {
                        list.familyActivitySelectionData = try? JSONEncoder().encode(merged(old, onto: newValue))
                    } else {
                        list.familyActivitySelectionData = data
                    }
                    BlockEngine.persistSelection(list.familyActivitySelectionData, mac: false)
                    try? context.save()
                    if lockState.shieldsShouldBeOn {
                        BlockEngine.applyShields()
                    }
                }
            }
            .onAppear {
                if let data = list.familyActivitySelectionData,
                   let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                    selection = saved
                }
            }
            #endif

            #if os(macOS)
            Section("Mac apps") {
                Text("Native macOS has no FamilyActivity picker. Lockin quits these apps while a block is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(list.macBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        if !addOnly {
                            Button(role: .destructive) {
                                list.macBundleIDs = list.macBundleIDs.filter { $0 != bundleID }
                                AppGroup.defaults.set(list.macBundleIDs, forKey: AppGroup.Key.macBundleIDs)
                                try? context.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                Button("Add Mac app…") { addMacApp() }
            }
            #endif

            Section("Website presets") {
                Text("Presets are a checklist. On iPhone, enforcement uses the Screen Time picker so Settings cannot bypass them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(WebsitePreset.allCases) { preset in
                    Toggle(preset.title, isOn: presetBinding(preset))
                        .disabled(addOnly && list.websitePresets.contains(preset))
                }
            }

            Section("Custom websites") {
                HStack {
                    TextField("example.com", text: $customURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    Button("Add") {
                        let host = normalizedHost(customURL)
                        guard !host.isEmpty else { return }
                        var current = list.customWebsites
                        if !current.contains(host) { current.append(host) }
                        list.customWebsites = current
                        customURL = ""
                        try? context.save()
                    }
                }
                ForEach(list.customWebsites, id: \.self) { host in
                    HStack {
                        Text(host)
                        Spacer()
                        if !addOnly {
                            Button(role: .destructive) {
                                list.customWebsites = list.customWebsites.filter { $0 != host }
                                try? context.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }

            Section("Xbox (nudge only)") {
                Toggle("Track Xbox", isOn: $list.xboxEnabled)
                    .disabled(addOnly)
                if list.xboxEnabled {
                    TextField("Gamertag", text: $list.xboxGamertag)
                        .disabled(addOnly)
                    Text("Lockin cannot hard-block the console. During a session it will notify you on a timer if this gamertag is online.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(list.name)
    }

    private func presetBinding(_ preset: WebsitePreset) -> Binding<Bool> {
        Binding(
            get: { list.websitePresets.contains(preset) },
            set: { on in
                if addOnly && list.websitePresets.contains(preset) && !on { return }
                var current = list.websitePresets
                if on, !current.contains(preset) { current.append(preset) }
                if !on { current.removeAll { $0 == preset } }
                list.websitePresets = current
                try? context.save()
            }
        )
    }

    private func normalizedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        return value
    }

    #if os(iOS)
    private func merged(_ old: FamilyActivitySelection, onto new: FamilyActivitySelection) -> FamilyActivitySelection {
        var result = new
        result.applicationTokens.formUnion(old.applicationTokens)
        result.categoryTokens.formUnion(old.categoryTokens)
        result.webDomainTokens.formUnion(old.webDomainTokens)
        return result
    }
    #endif

    #if os(macOS)
    private func addMacApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        var ids = list.macBundleIDs
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            if !ids.contains(id) { ids.append(id) }
        }
        list.macBundleIDs = ids
        AppGroup.defaults.set(ids, forKey: AppGroup.Key.macBundleIDs)
        try? context.save()
        if lockState.shieldsShouldBeOn {
            BlockEngine.applyShields()
        }
    }
    #endif
}
