import SwiftUI

// MARK: - Study time

extension Milestone {
    /// Blocked study time attached to this milestone via sessions, split into time already
    /// elapsed and time still scheduled. Uses segments when present (only those windows
    /// actually block), otherwise the whole session.
    func studyHours(now: Date = Date()) -> (done: Double, planned: Double) {
        var done: TimeInterval = 0
        var planned: TimeInterval = 0
        for session in sessions ?? [] {
            let segments = (session.segments ?? [])
            let ranges: [(Date, Date)] = segments.isEmpty
                ? [(session.startDate, session.endDate)]
                : segments.map { ($0.startDate, $0.endDate) }
            for (start, end) in ranges where end > start {
                if end <= now {
                    done += end.timeIntervalSince(start)
                } else if start >= now {
                    planned += end.timeIntervalSince(start)
                } else {
                    done += now.timeIntervalSince(start)
                    planned += end.timeIntervalSince(now)
                }
            }
        }
        return (done / 3600, planned / 3600)
    }

    var urgency: MilestoneUrgency {
        GradeCalculator.urgency(date: startDate, isFinished: isFinished)
    }
}

extension Zone {
    var gradeSummary: GradeSummary {
        GradeCalculator.summarize((milestones ?? []).map(\.gradeItem))
    }

    var unfinishedMilestones: [Milestone] {
        (milestones ?? []).filter { !$0.isFinished }.sorted { $0.startDate < $1.startDate }
    }

    var nextMilestone: Milestone? {
        let now = Date()
        return unfinishedMilestones.first { $0.startDate >= now }
    }
}

// MARK: - Formatting

enum ProgressFormat {
    /// "78.4%" / "80%": one decimal, trailing ".0" dropped.
    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return String(format: "%g", rounded)
    }

    static func hours(_ value: Double) -> String {
        if value < 0.05 { return "0h" }
        if value < 10 { return String(format: "%.1fh", value) }
        return "\(Int(value.rounded()))h"
    }

    /// "Today", "Tomorrow", "in 5d", "3d ago".
    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let d where d > 0: return "in \(d)d"
        default: return "\(-days)d ago"
        }
    }
}

extension GradeCalculator.Tone {
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

extension MilestoneUrgency {
    var label: String? {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due soon"
        default: return nil
        }
    }
    var color: Color {
        switch self {
        case .overdue: return .red
        case .dueSoon: return .orange
        case .upcoming: return .secondary
        case .finished: return .green
        }
    }
}

/// Small pill used for status / urgency.
struct Chip: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Thin horizontal bar, 0...1.
struct ThinBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}

extension View {
    func cardBackground() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
