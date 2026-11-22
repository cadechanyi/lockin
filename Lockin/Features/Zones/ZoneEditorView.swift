import SwiftUI
import SwiftData

struct ZoneEditorView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var lockState: LockState
    var zone: Zone?
    var onDone: () -> Void = {}

    @State private var title = ""
    @State private var colorHex = "#2563EB"
    @State private var isClass = true
    @State private var textbook = ""
    @State private var practice = ""
    @State private var custom: [NamedMaterial] = []
    @State private var milestoneTitle = ""
    @State private var milestoneScope = ""
    @State private var milestoneKind: EventKind = .quiz
    @State private var milestoneStart = Date()

    var body: some View {
        Form {
            Section("Zone") {
                TextField("Title", text: $title)
                Picker("Color", selection: $colorHex) {
                    ForEach(ZonePalette.options, id: \.hex) { option in
                        HStack {
                            Circle().fill(Color(hex: option.hex)).frame(width: 12, height: 12)
                            Text(option.name)
                        }.tag(option.hex)
                    }
                }
                Toggle("This is a class", isOn: $isClass)
            }

            if isClass {
                Section("Materials") {
                    TextField("Textbook & resources", text: $textbook, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Practice quizzes / tests", text: $practice, axis: .vertical)
                        .lineLimit(3...8)
                    ForEach($custom) { $item in
                        VStack {
                            TextField("Custom field name", text: $item.name)
                            TextField("Content", text: $item.content, axis: .vertical)
                        }
                    }
                    Button("Add custom field") {
                        custom.append(NamedMaterial(name: "", content: ""))
                    }
                }
            }

            if let zone {
                Section {
                    NavigationLink {
                        ZoneProgressView(zone: zone)
                    } label: {
                        Label("Grades & progress", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                Section("Milestones") {
                    ForEach(zone.milestones ?? [], id: \.id) { milestone in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title).font(.headline)
                            Text("\(milestone.kind.title) · \(DateFormatters.shortDate.string(from: milestone.startDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !milestone.scope.isEmpty {
                                Text(milestone.scope).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("New milestone title", text: $milestoneTitle)
                    Picker("Kind", selection: $milestoneKind) {
                        ForEach(EventKind.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Starts", selection: $milestoneStart)
                    TextField("Scope (optional)", text: $milestoneScope, axis: .vertical)
                    Button("Add milestone") {
                        guard !milestoneTitle.isEmpty else { return }
                        context.insert(Milestone(
                            title: milestoneTitle,
                            scope: milestoneScope,
                            kind: milestoneKind,
                            startDate: milestoneStart,
                            zone: zone
                        ))
                        milestoneTitle = ""
                        milestoneScope = ""
                        milestoneKind = .quiz
                        milestoneStart = Date()
                        try? context.save()
                    }
                }
            }

            Section {
                Button(zone == nil ? "Create zone" : "Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(zone == nil ? "New zone" : zone?.title ?? "Zone")
        .formStyle(.grouped)
        .onAppear { load() }
    }

    private func load() {
        guard let zone else { return }
        title = zone.title
        colorHex = zone.colorHex
        isClass = zone.isClass
        textbook = zone.textbookResources
        practice = zone.practiceQuizzes
        custom = zone.customMaterials
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = zone ?? Zone(title: trimmed, colorHex: colorHex, isClass: isClass)
        target.title = trimmed
        target.colorHex = colorHex
        target.isClass = isClass
        target.textbookResources = textbook
        target.practiceQuizzes = practice
        target.customMaterials = custom.filter { !$0.name.isEmpty || !$0.content.isEmpty }
        if zone == nil { context.insert(target) }
        try? context.save()
        onDone()
    }
}
