import SwiftUI
import SwiftData

/// Create or edit a milestone: what it is, when, how much it counts, where you are, and
/// the score once it is back. Scores / status / weight stay editable during a block;
/// title, kind, date and scope (the schedule + quiz material) freeze like the rest of
/// the plan.
struct MilestoneEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lockState: LockState

    var zone: Zone
    var milestone: Milestone?

    @State private var title = ""
    @State private var kind: EventKind = .assignment
    @State private var date = Date()
    @State private var scope = ""
    @State private var weight: Double = 0
    @State private var status: MilestoneStatus = .notStarted
    @State private var graded = false
    @State private var earned: Double = 0
    @State private var maxScore: Double = 100
    @State private var notes = ""
    @State private var confirmDelete = false

    private var scheduleLocked: Bool { lockState.isFrozen }
    private var isNew: Bool { milestone == nil }

    var body: some View {
        NavigationStack {
            Form {
                if scheduleLocked {
                    Section {
                        Label("A block is active. Title, date and scope are locked; you can still update status and scores.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("What") {
                    TextField("Title", text: $title)
                        .disabled(scheduleLocked)
                    Picker("Kind", selection: $kind) {
                        ForEach(EventKind.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(scheduleLocked)
                    DatePicker("Date", selection: $date)
                        .disabled(scheduleLocked)
                    TextField("Scope (what it covers)", text: $scope, axis: .vertical)
                        .lineLimit(2...6)
                        .disabled(scheduleLocked)
                }

                Section("Grade") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("0", value: $weight, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("% of course")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Graded", isOn: $graded)
                    if graded {
                        HStack {
                            Text("Score")
                            Spacer()
                            TextField("0", value: $earned, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("/")
                            TextField("100", value: $maxScore, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        if maxScore > 0 {
                            Text("= \(ProgressFormat.percent(earned / maxScore * 100))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("“Out of” must be greater than 0.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Picker("Status", selection: $status) {
                            ForEach(MilestoneStatus.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if weight <= 0 {
                        Text("Weight 0 means this does not count toward the course grade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let milestone {
                    let hours = milestone.studyHours()
                    Section("Study time") {
                        LabeledContent("Blocked so far", value: ProgressFormat.hours(hours.done))
                        LabeledContent("Scheduled ahead", value: ProgressFormat.hours(hours.planned))
                        Text("Counts sessions you attach to this milestone when scheduling.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if milestone != nil && !scheduleLocked {
                    Section {
                        Button("Delete milestone", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New milestone" : "Milestone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this milestone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let milestone { context.delete(milestone) }
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if graded && maxScore <= 0 { return false }
        if isNew && scheduleLocked { return false }
        return weight >= 0 && weight <= 100
    }

    private func load() {
        guard let milestone else { return }
        title = milestone.title
        kind = milestone.kind
        date = milestone.startDate
        scope = milestone.scope
        weight = milestone.weight
        status = milestone.status
        graded = milestone.isGraded
        earned = milestone.scoreEarned ?? 0
        maxScore = milestone.scoreMax
        notes = milestone.notes
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = milestone ?? Milestone(title: trimmed, zone: zone)
        if !scheduleLocked || isNew {
            target.title = trimmed
            target.kind = kind
            target.startDate = date
            target.scope = scope
        }
        target.weight = weight
        target.notes = notes
        target.scoreMax = maxScore > 0 ? maxScore : 100
        if graded {
            target.scoreEarned = earned
            target.status = .done
        } else {
            target.scoreEarned = nil
            target.status = status
        }
        if isNew { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
