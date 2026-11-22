import Foundation

struct BreakSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: String
    var startDate: Date?
    var endDate: Date?
    var durationMinutes: Int
    var intervalMinutes: Int
    var offsetMinutes: Int
    var segmentID: UUID?
}

struct SegmentSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var milestoneSubset: String
    var validated: Bool
}

struct SessionSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var zoneTitle: String
    var zoneColorHex: String
    var start: Date
    var end: Date
    var validationEnabled: Bool
    var milestoneTitle: String
    var blocklistName: String
    var xboxGamertag: String
    var xboxEnabled: Bool
    var macBundleIDs: [String]
    var familyActivitySelectionData: Data?
    var segments: [SegmentSnapshot]
    var breaks: [BreakSnapshot]
    var capDate: Date
}

struct ScheduleSnapshot: Codable, Hashable {
    var sessions: [SessionSnapshot]
    var updatedAt: Date
}

enum LockPhase: Equatable {
    case idle
    case activeBlock(sessionID: UUID, segmentID: UUID, ends: Date)
    case onBreak(sessionID: UUID, segmentID: UUID, until: Date)
    case overrun(sessionID: UUID, segmentID: UUID, cap: Date)

    var isFrozen: Bool {
        switch self {
        case .activeBlock, .overrun: return true
        default: return false
        }
    }

    var shieldsShouldBeOn: Bool {
        switch self {
        case .activeBlock, .overrun: return true
        default: return false
        }
    }

    var sessionID: UUID? {
        switch self {
        case .idle: return nil
        case .activeBlock(let id, _, _), .onBreak(let id, _, _), .overrun(let id, _, _):
            return id
        }
    }

    var segmentID: UUID? {
        switch self {
        case .idle: return nil
        case .activeBlock(_, let id, _), .onBreak(_, let id, _), .overrun(_, let id, _):
            return id
        }
    }
}

enum ScheduleEvaluator {
    static let maxSessionDays = 14

    /// Primary phase for single-session consumers: prefer a shields-on engagement, else any engagement.
    static func evaluate(snapshot: ScheduleSnapshot, now: Date = Date()) -> LockPhase {
        let all = evaluateAll(snapshot: snapshot, now: now)
        if let blocking = all.first(where: { $0.shieldsShouldBeOn }) {
            return blocking
        }
        return all.first ?? .idle
    }

    /// Every non-idle session engagement at `now`.
    /// Concurrent active blocks are prevented at save time; this still returns all matches defensively.
    static func evaluateAll(snapshot: ScheduleSnapshot, now: Date = Date()) -> [LockPhase] {
        snapshot.sessions
            .sorted { $0.start < $1.start }
            .compactMap { session -> LockPhase? in
                let phase = evaluate(session: session, now: now)
                return phase == .idle ? nil : phase
            }
    }

    static func evaluate(session: SessionSnapshot, now: Date) -> LockPhase {
        if now >= session.capDate { return .idle }

        let segments = session.segments.sorted { $0.start < $1.start }
        guard !segments.isEmpty else { return .idle }

        if session.validationEnabled {
            if let overdue = segments.first(where: { !$0.validated && $0.start <= now && now > $0.end }) {
                return .overrun(sessionID: session.id, segmentID: overdue.id, cap: session.capDate)
            }
        }

        for segment in segments {
            if session.validationEnabled && segment.validated { continue }
            guard now >= segment.start else { continue }
            if now <= segment.end {
                if let until = activeBreakEnd(session: session, segment: segment, now: now) {
                    return .onBreak(sessionID: session.id, segmentID: segment.id, until: until)
                }
                return .activeBlock(sessionID: session.id, segmentID: segment.id, ends: segment.end)
            }
        }
        return .idle
    }

    static func activeBreakEnd(session: SessionSnapshot, segment: SegmentSnapshot, now: Date) -> Date? {
        let breaks = session.breaks.filter { $0.segmentID == nil || $0.segmentID == segment.id }
        for item in breaks {
            if item.kind == "custom", let start = item.startDate, let end = item.endDate {
                if now >= start && now < end { return end }
                continue
            }
            if item.kind == "repeating" {
                let duration = TimeInterval(max(1, item.durationMinutes) * 60)
                let interval = TimeInterval(max(item.durationMinutes + 1, item.intervalMinutes) * 60)
                var cursor = segment.start.addingTimeInterval(TimeInterval(max(0, item.offsetMinutes) * 60))
                while cursor < segment.end {
                    let end = min(cursor.addingTimeInterval(duration), segment.end)
                    if now >= cursor && now < end { return end }
                    cursor = cursor.addingTimeInterval(interval)
                    if interval <= 0 { break }
                }
            }
        }
        return nil
    }

    static func session(in snapshot: ScheduleSnapshot, id: UUID) -> SessionSnapshot? {
        snapshot.sessions.first { $0.id == id }
    }

    static func segment(in snapshot: ScheduleSnapshot, id: UUID) -> SegmentSnapshot? {
        snapshot.sessions.flatMap(\.segments).first { $0.id == id }
    }
}
