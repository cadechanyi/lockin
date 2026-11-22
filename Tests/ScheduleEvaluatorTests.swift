import XCTest

final class ScheduleEvaluatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    private func session(
        validation: Bool,
        segments: [(start: Double, end: Double, validated: Bool)],
        breaks: [BreakSnapshot] = [],
        capDays: Double = 14
    ) -> (SessionSnapshot, [UUID]) {
        let segs = segments.map {
            SegmentSnapshot(
                id: UUID(),
                start: t0.addingTimeInterval(hours($0.start)),
                end: t0.addingTimeInterval(hours($0.end)),
                milestoneSubset: "",
                validated: $0.validated
            )
        }
        let snap = SessionSnapshot(
            id: UUID(), zoneTitle: "Z", zoneColorHex: "#000000",
            start: segs.first!.start, end: segs.last!.end,
            validationEnabled: validation, milestoneTitle: "M", blocklistName: "B",
            xboxGamertag: "", xboxEnabled: false, macBundleIDs: [],
            familyActivitySelectionData: nil, segments: segs, breaks: breaks,
            capDate: t0.addingTimeInterval(capDays * 86_400)
        )
        return (snap, segs.map(\.id))
    }

    func testIdleBeforeStart() {
        let (s, _) = session(validation: false, segments: [(1, 2, false)])
        XCTAssertEqual(ScheduleEvaluator.evaluate(session: s, now: t0), .idle)
    }

    func testActiveDuringSegment() {
        let (s, ids) = session(validation: false, segments: [(0, 2, false)])
        let phase = ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(1)))
        XCTAssertEqual(phase, .activeBlock(sessionID: s.id, segmentID: ids[0], ends: s.segments[0].end))
        XCTAssertTrue(phase.shieldsShouldBeOn)
    }

    func testTimeOnlySessionUnlocksWhenClockEnds() {
        let (s, _) = session(validation: false, segments: [(0, 2, false)])
        XCTAssertEqual(ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(3))), .idle)
    }

    func testValidatedSessionOverrunsInsteadOfUnlocking() {
        let (s, ids) = session(validation: true, segments: [(0, 2, false)])
        let phase = ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(3)))
        XCTAssertEqual(phase, .overrun(sessionID: s.id, segmentID: ids[0], cap: s.capDate))
        XCTAssertTrue(phase.shieldsShouldBeOn)
        XCTAssertTrue(phase.isFrozen)
    }

    func testValidatedSegmentUnlocks() {
        let (s, _) = session(validation: true, segments: [(0, 2, true)])
        XCTAssertEqual(ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(1))), .idle)
    }

    func testHardCapEndsOverrun() {
        let (s, _) = session(validation: true, segments: [(0, 2, false)], capDays: 1)
        XCTAssertEqual(ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(25))), .idle)
    }

    func testSegmentGapIsUnblocked() {
        let (s, _) = session(validation: false, segments: [(0, 2, false), (24, 26, false)])
        XCTAssertEqual(ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(12))), .idle)
        XCTAssertTrue(ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(25))).shieldsShouldBeOn)
    }

    func testCustomBreakLiftsShields() {
        let brk = BreakSnapshot(
            id: UUID(), kind: "custom",
            startDate: t0.addingTimeInterval(hours(1)), endDate: t0.addingTimeInterval(hours(1.5)),
            durationMinutes: 5, intervalMinutes: 60, offsetMinutes: 55, segmentID: nil
        )
        let (s, _) = session(validation: false, segments: [(0, 3, false)], breaks: [brk])
        let phase = ScheduleEvaluator.evaluate(session: s, now: t0.addingTimeInterval(hours(1.2)))
        guard case .onBreak = phase else { return XCTFail("expected break, got \(phase)") }
        XCTAssertFalse(phase.shieldsShouldBeOn)
    }

    func testRepeatingBreak() {
        // 5 min break starting 55 min into each 60 min cycle.
        let brk = BreakSnapshot(
            id: UUID(), kind: "repeating", startDate: nil, endDate: nil,
            durationMinutes: 5, intervalMinutes: 60, offsetMinutes: 55, segmentID: nil
        )
        let (s, _) = session(validation: false, segments: [(0, 3, false)], breaks: [brk])
        let during = t0.addingTimeInterval(57 * 60)
        let outside = t0.addingTimeInterval(30 * 60)
        guard case .onBreak = ScheduleEvaluator.evaluate(session: s, now: during) else { return XCTFail("expected break") }
        XCTAssertTrue(ScheduleEvaluator.evaluate(session: s, now: outside).shieldsShouldBeOn)
    }
}
