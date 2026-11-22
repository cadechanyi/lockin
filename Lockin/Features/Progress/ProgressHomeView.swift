import SwiftUI
import SwiftData

/// Progress tab: every course at a glance, plus what is coming up next across all of them.
struct ProgressHomeView: View {
    @Query(sort: \Zone.title) private var zones: [Zone]
    @State private var path = NavigationPath()

    /// Classes always show; other zones only once they have milestones.
    private var trackedZones: [Zone] {
        zones.filter { $0.isClass || !($0.milestones ?? []).isEmpty }
    }

    private var upNext: [(zone: Zone, milestone: Milestone)] {
        trackedZones
            .flatMap { zone in zone.unfinishedMilestones.map { (zone: zone, milestone: $0) } }
            .sorted { $0.milestone.startDate < $1.milestone.startDate }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if trackedZones.isEmpty {
                        Text("Add a class in the Zones tab, then track its milestones and grades here.")
                            .foregroundStyle(.secondary)
                            .cardBackground()
                    } else {
                        if !upNext.isEmpty { upNextCard }
                        coursesSection
                    }
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationDestination(for: UUID.self) { id in
                if let zone = zones.first(where: { $0.id == id }) {
                    ZoneProgressView(zone: zone)
                }
            }
        }
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Up next").font(.headline)
            ForEach(Array(upNext.enumerated()), id: \.element.milestone.id) { index, item in
                Button {
                    path.append(item.zone.id)
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: item.zone.colorHex))
                            .frame(width: 5, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.milestone.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(item.zone.title) · \(item.milestone.kind.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ProgressFormat.relativeDay(item.milestone.startDate))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.milestone.urgency.color)
                            Text(item.milestone.status.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < upNext.count - 1 { Divider() }
            }
        }
        .cardBackground()
    }

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Courses").font(.headline)
            ForEach(trackedZones, id: \.id) { zone in
                Button {
                    path.append(zone.id)
                } label: {
                    CourseCard(zone: zone)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CourseCard: View {
    var zone: Zone

    private var summary: GradeSummary { zone.gradeSummary }
    private var accent: Color { Color(hex: zone.colorHex) }
    private var overdue: Int { (zone.milestones ?? []).filter { $0.urgency == .overdue }.count }
    private var dueSoon: Int { (zone.milestones ?? []).filter { $0.urgency == .dueSoon }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(zone.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                if let average = summary.currentAverage {
                    Text(ProgressFormat.percent(average))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GradeCalculator.tone(for: average, target: zone.targetGrade).color)
                } else {
                    Text("No grades yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ThinBar(fraction: summary.gradedWeight / 100, color: accent)

            HStack(spacing: 8) {
                Text("Target \(ProgressFormat.percent(zone.targetGrade))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if overdue > 0 { Chip(text: "\(overdue) overdue", color: .red) }
                if dueSoon > 0 { Chip(text: "\(dueSoon) due this week", color: .orange) }
                Spacer()
                if let next = zone.nextMilestone {
                    Text("\(next.title) \(ProgressFormat.relativeDay(next.startDate).lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent, lineWidth: 2))
    }
}
