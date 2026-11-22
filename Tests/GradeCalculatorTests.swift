import XCTest

final class GradeCalculatorTests: XCTestCase {
    func testEmptyHasNoAverage() {
        let s = GradeCalculator.summarize([])
        XCTAssertNil(s.currentAverage)
        XCTAssertEqual(s.earnedPoints, 0)
        XCTAssertEqual(s.remainingWeight, 100)
        XCTAssertEqual(s.ceiling, 100)
    }

    func testWeightedAverageOverGradedWorkOnly() {
        // 20% midterm at 80/100, 10% assignment at 45/50 (90%), 30% final not graded.
        let items = [
            GradeItem(weight: 20, earned: 80, max: 100),
            GradeItem(weight: 10, earned: 45, max: 50),
            GradeItem(weight: 30)
        ]
        let s = GradeCalculator.summarize(items)
        XCTAssertEqual(s.gradedWeight, 30, accuracy: 0.0001)
        XCTAssertEqual(s.earnedPoints, 25, accuracy: 0.0001)               // 16 + 9
        XCTAssertEqual(s.currentAverage!, 25.0 / 30.0 * 100, accuracy: 0.0001)
        XCTAssertEqual(s.enteredWeight, 60, accuracy: 0.0001)
        XCTAssertEqual(s.unenteredWeight, 40, accuracy: 0.0001)
        XCTAssertEqual(s.remainingWeight, 70, accuracy: 0.0001)             // 100 - graded
        XCTAssertEqual(s.floor, 25, accuracy: 0.0001)
        XCTAssertEqual(s.ceiling, 95, accuracy: 0.0001)
        XCTAssertEqual(s.projected!, 25 + 70 * (25.0 / 30.0), accuracy: 0.0001)
    }

    func testZeroWeightAndInvalidMaxAreIgnored() {
        let items = [
            GradeItem(weight: 0, earned: 100, max: 100),
            GradeItem(weight: 10, earned: 5, max: 0),
            GradeItem(weight: 10, earned: 8, max: 10)
        ]
        let s = GradeCalculator.summarize(items)
        XCTAssertEqual(s.gradedWeight, 10, accuracy: 0.0001)
        XCTAssertEqual(s.earnedPoints, 8, accuracy: 0.0001)
        XCTAssertEqual(s.currentAverage!, 80, accuracy: 0.0001)
    }

    func testOverweightFlag() {
        let s = GradeCalculator.summarize([GradeItem(weight: 60), GradeItem(weight: 50)])
        XCTAssertTrue(s.overweight)
        XCTAssertEqual(s.unenteredWeight, 0)
    }

    func testOutlookNeeds() {
        // 50 points banked from 50% graded. Target 80 -> need 30 of remaining 50 = 60%.
        let s = GradeCalculator.summarize([GradeItem(weight: 50, earned: 100, max: 100)])
        XCTAssertEqual(s.earnedPoints, 50)
        switch GradeCalculator.outlook(for: s, target: 80) {
        case .needs(let required): XCTAssertEqual(required, 60, accuracy: 0.0001)
        default: XCTFail("expected .needs")
        }
    }

    func testOutlookSecured() {
        let s = GradeCalculator.summarize([GradeItem(weight: 90, earned: 90, max: 100)])
        XCTAssertEqual(GradeCalculator.outlook(for: s, target: 80), .secured)
    }

    func testOutlookUnreachable() {
        // 10 points banked of 50 graded; best case 10 + 50 = 60 < 80.
        let s = GradeCalculator.summarize([GradeItem(weight: 50, earned: 10, max: 50)])
        XCTAssertEqual(s.earnedPoints, 10, accuracy: 0.0001)
        XCTAssertEqual(GradeCalculator.outlook(for: s, target: 80), .unreachable(best: 60))
    }

    func testOutlookWhenCourseFullyGradedBelowTarget() {
        let s = GradeCalculator.summarize([GradeItem(weight: 100, earned: 70, max: 100)])
        XCTAssertEqual(GradeCalculator.outlook(for: s, target: 80), .unreachable(best: 70))
    }

    func testRequiredScoreOnSpecificItem() {
        // 40 banked. Final worth 40, other remaining 20 assumed at 75% = 15.
        let s = GradeCalculator.summarize([GradeItem(weight: 40, earned: 100, max: 100)])
        let needed = GradeCalculator.requiredScore(forItemWeight: 40, summary: s, target: 80, assumedOther: 75)
        // remaining = 60; other = 20 -> 15 expected; (80 - 40 - 15)/40 = 62.5%
        XCTAssertEqual(needed!, 62.5, accuracy: 0.0001)
    }

    func testUrgency() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        XCTAssertEqual(GradeCalculator.urgency(date: now - day, isFinished: false, now: now), .overdue)
        XCTAssertEqual(GradeCalculator.urgency(date: now + 3 * day, isFinished: false, now: now), .dueSoon)
        XCTAssertEqual(GradeCalculator.urgency(date: now + 20 * day, isFinished: false, now: now), .upcoming)
        XCTAssertEqual(GradeCalculator.urgency(date: now - day, isFinished: true, now: now), .finished)
    }
}
