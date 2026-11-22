import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class LockState: ObservableObject {
    @Published private(set) var phase: LockPhase = .idle
    @Published private(set) var activePhases: [LockPhase] = []
    @Published private(set) var snapshot = ScheduleSnapshot(sessions: [], updatedAt: .distantPast)
    @Published var showValidation = false
    @Published var validationSessionID: UUID?

    private var timer: AnyCancellable?

    var isFrozen: Bool { activePhases.contains(where: \.isFrozen) }
    var canEdit: Bool { !isFrozen }
    var shieldsShouldBeOn: Bool { activePhases.contains(where: \.shieldsShouldBeOn) }

    var activeSession: SessionSnapshot? {
        guard let id = phase.sessionID else { return nil }
        return ScheduleEvaluator.session(in: snapshot, id: id)
    }

    var activeSegment: SegmentSnapshot? {
        guard let id = phase.segmentID else { return nil }
        return ScheduleEvaluator.segment(in: snapshot, id: id)
    }

    var activeSessions: [SessionSnapshot] {
        let ids = Set(activePhases.compactMap(\.sessionID))
        return snapshot.sessions.filter { ids.contains($0.id) }
    }

    func start() {
        timer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func refresh(sessions: [StudySession]) {
        snapshot = SnapshotBuilder.build(sessions: sessions)
        BlockEngine.persist(snapshot: snapshot)
        tick()
        #if os(iOS)
        BlockEngine.startMonitoring(snapshot: snapshot)
        #endif
    }

    func tick() {
        let previous = activePhases
        activePhases = ScheduleEvaluator.evaluateAll(snapshot: snapshot)
        phase = ScheduleEvaluator.evaluate(snapshot: snapshot)
        BlockEngine.applyShieldsIfNeeded()

        let previousBlocking = Set(previous.filter(\.shieldsShouldBeOn).compactMap(\.sessionID))
        let currentBlocking = Set(activePhases.filter(\.shieldsShouldBeOn).compactMap(\.sessionID))

        for phase in activePhases {
            if case .onBreak(let sessionID, _, _) = phase,
               previous.contains(where: {
                   if case .activeBlock(let id, _, _) = $0 { return id == sessionID }
                   return false
               }) {
                NotificationService.post(
                    title: "Break started",
                    body: "Shields are down for your scheduled break. Usage is logged."
                )
                logBreakStart(sessionID: sessionID)
            }
            if case .activeBlock(let sessionID, _, _) = phase,
               previous.contains(where: {
                   if case .onBreak(let id, _, _) = $0 { return id == sessionID }
                   return false
               }) {
                logBreakEnd(sessionID: sessionID)
            }
            if case .overrun = phase,
               previous.contains(where: {
                   if case .activeBlock(let id, _, _) = $0, id == phase.sessionID { return true }
                   return false
               }) {
                NotificationService.post(
                    title: "Session overrun",
                    body: "Time is up. Apps stay locked until you validate in Lockin."
                )
            }
        }

        // If a session left blocking while another remains, no extra work — shields stay merged.
        _ = previousBlocking
        _ = currentBlocking
    }

    func openValidation(for sessionID: UUID? = nil) {
        validationSessionID = sessionID ?? phase.sessionID
        showValidation = true
    }

    func markValidated(sessionID: UUID, segmentID: UUID, context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        if let segment = (session.segments ?? []).first(where: { $0.id == segmentID }) {
            segment.validatedAt = Date()
        } else if session.id == segmentID {
            let implicit = SessionSegment()
            implicit.id = session.id
            implicit.startDate = session.startDate
            implicit.endDate = session.endDate
            implicit.validatedAt = Date()
            implicit.session = session
            context.insert(implicit)
        }
        try? context.save()
        AppGroup.defaults.set(true, forKey: AppGroup.Key.validated)
        refresh(sessions: sessions)
    }

    func startNextSegmentNow(sessionID: UUID, context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let upcoming = (session.segments ?? [])
            .filter { $0.validatedAt == nil && $0.startDate > Date() }
            .sorted { $0.startDate < $1.startDate }
            .first
        guard let next = upcoming else { return }
        let duration = next.endDate.timeIntervalSince(next.startDate)
        next.startDate = Date()
        next.endDate = Date().addingTimeInterval(max(60, duration))
        try? context.save()
        refresh(sessions: sessions)
    }

    private func logBreakStart(sessionID: UUID) {
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "lockin.breakStartedAt")
        AppGroup.defaults.set(sessionID.uuidString, forKey: "lockin.breakSessionID")
    }

    private func logBreakEnd(sessionID: UUID) {
        let start = Date(timeIntervalSince1970: AppGroup.defaults.double(forKey: "lockin.breakStartedAt"))
        NotificationCenter.default.post(
            name: .lockinBreakEnded,
            object: nil,
            userInfo: ["sessionID": sessionID, "startedAt": start, "endedAt": Date()]
        )
    }
}

extension Notification.Name {
    static let lockinBreakEnded = Notification.Name("lockin.breakEnded")
    static let lockinOpenValidation = Notification.Name("lockin.openValidation")
}
