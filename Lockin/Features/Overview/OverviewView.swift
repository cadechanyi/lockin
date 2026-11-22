import SwiftUI
import SwiftData

struct OverviewView: View {
    @EnvironmentObject private var lockState: LockState
    @EnvironmentObject private var sync: SyncMonitor
    @Query(sort: \Zone.title) private var zones: [Zone]
    @Query(sort: \StudySession.startDate) private var sessions: [StudySession]
    @Query(sort: \XboxPresenceLog.timestamp, order: .reverse) private var xboxLogs: [XboxPresenceLog]
    @Query(sort: \BreakUsageLog.startedAt, order: .reverse) private var breakLogs: [BreakUsageLog]
    @Query(sort: \ValidationAttempt.timestamp, order: .reverse) private var attempts: [ValidationAttempt]
    @State private var showSettings = false
    @State private var dashRange: DashRange = .week

    enum DashRange: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    syncBanner
                    activeCard
                    Picker("Range", selection: $dashRange) {
                        ForEach(DashRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DashboardCard(
                        title: dashRange.title + " progress",
                        sessions: sessionsInRange,
                        attempts: attemptsInRange,
                        xboxLogs: xboxInRange,
                        breakLogs: breaksInRange
                    )
                    zoneProgress
                }
                .padding()
            }
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    /// Only shown when this device is NOT syncing, so a silent local-only fallback is obvious.
    @ViewBuilder
    private var syncBanner: some View {
        if !sync.mode.isSyncing {
            Button { showSettings = true } label: {
                Label("Not syncing with iCloud. This device is using its own copy of your data. Tap to see why.", systemImage: "icloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now")
                .font(.headline)
            if lockState.activePhases.isEmpty {
                Text("No active block. Plan the term, then schedule a session.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lockState.activePhases.enumerated()), id: \.offset) { _, phase in
                    activePhaseRow(phase)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func activePhaseRow(_ phase: LockPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .idle:
                EmptyView()
            case .activeBlock(_, _, let ends):
                statusRow(title: "Blocking", color: .red, detail: "Until \(DateFormatters.shortTime.string(from: ends))")
            case .onBreak(_, _, let until):
                statusRow(title: "Break", color: .orange, detail: "Shields down until \(DateFormatters.shortTime.string(from: until))")
            case .overrun(_, _, let cap):
                statusRow(title: "Overrun — still locked", color: .purple, detail: "Hard cap \(DateFormatters.shortDate.string(from: cap))")
            }

            if let sessionID = phase.sessionID,
               let session = ScheduleEvaluator.session(in: lockState.snapshot, id: sessionID) {
                Text(session.zoneTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: session.zoneColorHex))
                if !session.milestoneTitle.isEmpty {
                    Text(session.milestoneTitle)
                }
                if let segmentID = phase.segmentID,
                   let segment = ScheduleEvaluator.segment(in: lockState.snapshot, id: segmentID),
                   !segment.milestoneSubset.isEmpty {
                    Text("Segment: \(segment.milestoneSubset)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if session.validationEnabled, phase.shieldsShouldBeOn || {
                    if case .overrun = phase { return true }
                    return false
                }() {
                    Button("Validate to unlock") {
                        lockState.openValidation(for: session.id)
                    }
                    .buttonStyle(.borderedProminent)
                } else if !session.validationEnabled, phase.shieldsShouldBeOn {
                    Text("Time-only session. Unlocks when the clock ends.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusRow(title: String, color: Color, detail: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var zoneProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zones")
                .font(.headline)
            ForEach(zones, id: \.id) { zone in
                let zoneSessions = sessions.filter { $0.zone?.id == zone.id }
                let milestones = zone.milestones ?? []
                let validated = zoneSessions.flatMap { $0.segments ?? [] }.filter { $0.validatedAt != nil }.count
                let summary = zone.gradeSummary
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: zone.colorHex))
                        .frame(width: 8, height: 28)
                    VStack(alignment: .leading) {
                        Text(zone.title).font(.subheadline.weight(.semibold))
                        Text(zoneDetail(milestones: milestones.count, validated: validated, zone: zone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let average = summary.currentAverage {
                        Text(ProgressFormat.percent(average))
                            .font(.headline)
                            .foregroundStyle(GradeCalculator.tone(for: average, target: zone.targetGrade).color)
                    }
                }
            }
            if zones.isEmpty {
                Text("Add a zone to get started.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func zoneDetail(milestones: Int, validated: Int, zone: Zone) -> String {
        var text = "\(milestones) milestones · \(validated) segments validated"
        if let next = zone.nextMilestone {
            text += " · next: \(next.title) \(ProgressFormat.relativeDay(next.startDate).lowercased())"
        }
        return text
    }

    private var rangeInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch dashRange {
        case .day:
            let start = cal.startOfDay(for: now)
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start) ?? now)
        case .week:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 7, to: start) ?? now)
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start) ?? now)
        }
    }

    private var sessionsInRange: [StudySession] {
        sessions.filter { rangeInterval.intersects(DateInterval(start: $0.startDate, end: $0.endDate)) }
    }

    private var attemptsInRange: [ValidationAttempt] {
        attempts.filter { rangeInterval.contains($0.timestamp) }
    }

    private var xboxInRange: [XboxPresenceLog] {
        xboxLogs.filter { rangeInterval.contains($0.timestamp) }
    }

    private var breaksInRange: [BreakUsageLog] {
        breakLogs.filter { rangeInterval.contains($0.startedAt) }
    }
}
