import Foundation

/// One graded (or gradable) piece of a course. Pure value type so the math is testable
/// without SwiftData.
struct GradeItem: Equatable {
    /// Share of the course grade in percent (a 20% midterm is `20`).
    var weight: Double
    /// Score earned, or `nil` if not graded yet.
    var earned: Double?
    /// Maximum score (e.g. 50 for "42/50").
    var max: Double

    init(weight: Double, earned: Double? = nil, max: Double = 100) {
        self.weight = weight
        self.earned = earned
        self.max = max
    }

    /// Only items that count toward the grade and have a score participate in averages.
    var isGraded: Bool { weight > 0 && max > 0 && earned != nil }
    var counts: Bool { weight > 0 }

    /// Grade points contributed toward the 100-point course total.
    var points: Double {
        guard isGraded, let earned else { return 0 }
        return weight * earned / max
    }
}

struct GradeSummary: Equatable {
    /// Total weight of every item entered (even ungraded).
    var enteredWeight: Double
    /// Weight of items that already have a score.
    var gradedWeight: Double
    /// Course weight still to be earned: everything not yet graded, including weight the
    /// student has not entered at all. Never negative.
    var remainingWeight: Double
    /// Weight of the course not yet entered into the app (100 − entered).
    var unenteredWeight: Double
    /// Points banked so far out of 100.
    var earnedPoints: Double
    /// Average over graded work only, in percent. `nil` if nothing is graded.
    var currentAverage: Double?
    /// Worst case: zero on everything left.
    var floor: Double { earnedPoints }
    /// Best case: perfect on everything left.
    var ceiling: Double { earnedPoints + remainingWeight }
    /// Final grade if the rest of the course goes like the graded work so far.
    var projected: Double? {
        guard let currentAverage else { return nil }
        return earnedPoints + remainingWeight * currentAverage / 100
    }
    /// True when entered weights add past 100% (probably a typo).
    var overweight: Bool { enteredWeight > 100.0001 }
}

/// What it takes to reach a target grade.
enum TargetOutlook: Equatable {
    /// Already banked enough points; nothing left can lose it.
    case secured
    /// Need this average (percent) on everything remaining.
    case needs(Double)
    /// Even perfect marks on everything left falls short.
    case unreachable(best: Double)
}

enum MilestoneUrgency: Equatable {
    case finished, overdue, dueSoon, upcoming
}

enum GradeCalculator {
    static func summarize(_ items: [GradeItem]) -> GradeSummary {
        let counting = items.filter(\.counts)
        let entered = counting.reduce(0) { $0 + $1.weight }
        let graded = counting.filter(\.isGraded)
        let gradedWeight = graded.reduce(0) { $0 + $1.weight }
        let points = graded.reduce(0) { $0 + $1.points }
        let average: Double? = gradedWeight > 0 ? points / gradedWeight * 100 : nil
        return GradeSummary(
            enteredWeight: entered,
            gradedWeight: gradedWeight,
            remainingWeight: Swift.max(0, 100 - gradedWeight),
            unenteredWeight: Swift.max(0, 100 - entered),
            earnedPoints: points,
            currentAverage: average
        )
    }

    static func outlook(for summary: GradeSummary, target: Double) -> TargetOutlook {
        if summary.earnedPoints >= target { return .secured }
        guard summary.remainingWeight > 0 else {
            return .unreachable(best: summary.ceiling)
        }
        let required = (target - summary.earnedPoints) / summary.remainingWeight * 100
        if required > 100 { return .unreachable(best: summary.ceiling) }
        return .needs(Swift.max(0, required))
    }

    /// Score needed on one specific item (weight `itemWeight`) to hit `target`, assuming
    /// all *other* remaining work lands at `assumedOther` percent.
    static func requiredScore(
        forItemWeight itemWeight: Double,
        summary: GradeSummary,
        target: Double,
        assumedOther: Double
    ) -> Double? {
        guard itemWeight > 0 else { return nil }
        let otherRemaining = Swift.max(0, summary.remainingWeight - itemWeight)
        let expectedOther = otherRemaining * assumedOther / 100
        return (target - summary.earnedPoints - expectedOther) / itemWeight * 100
    }

    static func urgency(
        date: Date,
        isFinished: Bool,
        now: Date = Date(),
        soonDays: Int = 7
    ) -> MilestoneUrgency {
        if isFinished { return .finished }
        if date < now { return .overdue }
        let soon = now.addingTimeInterval(TimeInterval(soonDays) * 86_400)
        return date <= soon ? .dueSoon : .upcoming
    }

    /// How a grade compares to the target, used only for color.
    static func tone(for percent: Double, target: Double) -> Tone {
        if percent >= target { return .good }
        if percent >= target - 10 { return .warning }
        return .danger
    }

    enum Tone { case good, warning, danger }
}
