import SwiftUI
import SwiftData

struct BlocklistsView: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context
    @Query(sort: \Blocklist.name) private var lists: [Blocklist]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                EntityCardGrid {
                    ForEach(lists, id: \.id) { list in
                        Button {
                            path.append(list.id)
                        } label: {
                            EntityCard(
                                title: list.name,
                                subtitle: blocklistSubtitle(list),
                                borderColor: Color.secondary.opacity(0.55),
                                fill: Color.secondary.opacity(0.07)
                            ) {
                                if list.xboxEnabled {
                                    Label(list.xboxGamertag.isEmpty ? "Xbox tracking" : list.xboxGamertag, systemImage: "logo.xbox")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if lockState.canEdit {
                                Button("Delete", role: .destructive) {
                                    context.delete(list)
                                    try? context.save()
                                }
                            }
                        }
                    }

                    AddEntityCard(title: "Add new Blocklist") {
                        createAndOpen()
                    }
                }
            }
            .navigationTitle("Blocklist")
            .navigationDestination(for: UUID.self) { id in
                if let list = lists.first(where: { $0.id == id }) {
                    BlocklistEditorView(list: list)
                }
            }
        }
    }

    private func blocklistSubtitle(_ list: Blocklist) -> String {
        var parts: [String] = []
        #if os(macOS)
        if !list.macBundleIDs.isEmpty {
            parts.append("\(list.macBundleIDs.count) Mac apps")
        }
        #endif
        if !list.websitePresets.isEmpty || !list.customWebsites.isEmpty {
            parts.append("\(list.websitePresets.count + list.customWebsites.count) sites")
        }
        if list.familyActivitySelectionData != nil {
            parts.append("Screen Time apps")
        }
        return parts.isEmpty ? "Tap to configure apps & sites" : parts.joined(separator: " · ")
    }

    private func createAndOpen() {
        let list = Blocklist(name: "New block list")
        context.insert(list)
        try? context.save()
        path.append(list.id)
    }
}
