import SwiftUI
import SwiftData

/// One course: current grade, what it takes to hit the target, and every milestone.
struct ZoneProgressView: View {
    @Bindable var zone: Zone
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context

    @State private var editing: Milestone?
    @State private var showNew = false

    private var accent: Color { Color(hex: zone.colorHex) }
    private var summary: GradeSummary { zone.gradeSummary }

    private var milestones: [Milestone] { zone.milestones ?? [] }
    private var attention: [Milestone] {
        milestones.filter { $0.urgency == .overdue || $0.urgency == .dueSoon }
            .sorted { $0.startDate < $1.startDate }
    }
    private var upcoming: [Milestone] {
        milestones.filter { $0.urgency == .upcoming }.sorted { $0.startDate < $1.startDate }
    }
    private var finished: [Milestone] {
        milestones.filter { $0.urgency == .finished }.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                gradeCard
                if !attention.isEmpty {
                    section("Needs attention", milestones: attention)
                }
                if !upcoming.isEmpty {
                    section("Upcoming", milestones: upcoming)
                }
                if !finished.isEmpty {
                    section("Finished", milestones: finished)
                }
                if milestones.isEmpty {
                    Text("No milestones yet. Add assignments, quizzes and exams with their weights to track your grade.")
                        .foregroundStyle(.secondary)
                        .cardBackground()
                }
            }
            .padding()
        }
        .navigationTitle(zone.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNew = true
                } label: {
                    Label("Add milestone", systemImage: "plus")
                }
                .disabled(lockState.isFrozen)
            }
        }
        .sheet(isPresented: $showNew) {
            MilestoneEditorView(zone: zone, milestone: nil)
        }
        .sheet(item: $editing) { milestone in
            MilestoneEditorView(zone: zone, milestone: milestone)
        }
    }

    // MARK: Grade

    private var gradeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current grade")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let average = summary.currentAverage {
                        Text(ProgressFormat.percent(average))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(GradeCalculator.tone(for: average, target: zone.targetGrade).color)
                    } else {
                        Text("—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Stepper(value: $zone.targetGrade, in: 40...100, step: 1) {
                        Text(ProgressFormat.percent(zone.targetGrade))
                            .font(.title3.weight(.semibold))
                    }
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ThinBar(fraction: summary.gradedWeight / 100, color: accent)
                Text("\(ProgressFormat.percent(summary.gradedWeight)) of the course graded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                stat("Worst case", summary.floor)
                stat("On pace for", summary.projected)
                stat("Best case", summary.ceiling)
            }

            outlookView

            if summary.overweight {
                warning("Weights add up to \(ProgressFormat.percent(summary.enteredWeight)). Check for a typo.")
            } else if summary.unenteredWeight > 0.5 && !milestones.isEmpty {
                warning("Only \(ProgressFormat.percent(summary.enteredWeight)) of the course weight is entered. Add the rest (e.g. the final) so these numbers are accurate.")
            }
        }
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.6), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var outlookView: some View {
        let target = ProgressFormat.percent(zone.targetGrade)
        switch GradeCalculator.outlook(for: summary, target: zone.targetGrade) {
        case .secured:
            Label("\(target) is secured. You have \(ProgressFormat.number(summary.earnedPoints)) points banked.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.medium))
        case .needs(let required):
            Label("To reach \(target) you need an average of \(ProgressFormat.percent(required)) on the remaining \(ProgressFormat.percent(summary.remainingWeight)) of the course.", systemImage: "target")
                .foregroundStyle(required > 90 ? .orange : .primary)
                .font(.subheadline.weight(.medium))
        case .unreachable(let best):
            Label("\(target) is out of reach. The best possible final grade is \(ProgressFormat.percent(best)).", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline.weight(.medium))
        }
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map(ProgressFormat.percent) ?? "—")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    // MARK: Milestone lists

    private func section(_ title: String, milestones: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneRow(milestone: milestone, accent: accent) { editing = milestone }
                    if index < milestones.count - 1 { Divider() }
                }
            }
            .cardBackground()
        }
    }
}

private struct MilestoneRow: View {
    var milestone: Milestone
    var accent: Color
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: milestone.isGraded ? "checkmark.circle.fill" : milestone.status.systemImage)
                    .foregroundStyle(milestone.isFinished ? Color.green : accent)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let label = milestone.urgency.label {
                            Chip(text: label, color: milestone.urgency.color)
                        }
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts = [milestone.kind.title, DateFormatters.shortDate.string(from: milestone.startDate)]
        if milestone.weight > 0 { parts.append("\(ProgressFormat.percent(milestone.weight)) of grade") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if let percent = milestone.scorePercent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProgressFormat.percent(percent)).font(.headline)
                Text("\(ProgressFormat.number(milestone.scoreEarned ?? 0))/\(ProgressFormat.number(milestone.scoreMax))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if milestone.isFinished {
            Text("Done").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProgressFormat.relativeDay(milestone.startDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(milestone.urgency.color)
                Text(milestone.status.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
