import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySession.startDate) private var sessions: [StudySession]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @AppStorage(DeviceSettings.Key.onboardingComplete) private var onboardingComplete = false
    @Query(sort: \XboxPresenceLog.timestamp, order: .reverse) private var xboxLogs: [XboxPresenceLog]

    @State private var lastXboxPoll = Date.distantPast

    private var needsOnboarding: Bool { !onboardingComplete }

    /// Onboarding used to be stored in the synced settings row. Carry an old "done" over
    /// so existing installs are not asked to set up again.
    private func migrateLegacyOnboarding() {
        guard !onboardingComplete, let legacy = settings.first else { return }
        #if os(macOS)
        if legacy.macOnboardingComplete { onboardingComplete = true }
        #else
        if legacy.onboardingComplete { onboardingComplete = true }
        #endif
    }

    /// Fingerprint so CloudKit merges (e.g. validatedAt) trigger a local schedule rebuild.
    private var scheduleToken: String {
        sessions.map { session in
            let segments = (session.segments ?? [])
                .map {
                    "\($0.id.uuidString):\($0.validatedAt?.timeIntervalSince1970 ?? -1):\($0.startDate.timeIntervalSince1970):\($0.endDate.timeIntervalSince1970)"
                }
                .sorted()
                .joined(separator: ",")
            let breaks = (session.breaks ?? [])
                .map { "\($0.id.uuidString):\($0.startDate?.timeIntervalSince1970 ?? -1):\($0.endDate?.timeIntervalSince1970 ?? -1)" }
                .sorted()
                .joined(separator: ",")
            return "\(session.id.uuidString):\(session.startDate.timeIntervalSince1970):\(session.endDate.timeIntervalSince1970):\(session.validationEnabled):\(segments):\(breaks)"
        }
        .sorted()
        .joined(separator: "|")
    }

    private var validationPair: (SessionSnapshot, SegmentSnapshot)? {
        let sessionID = lockState.validationSessionID ?? lockState.phase.sessionID
        guard let sessionID,
              let session = ScheduleEvaluator.session(in: lockState.snapshot, id: sessionID) else { return nil }
        let segment: SegmentSnapshot? = {
            if let preferred = lockState.activePhases.first(where: { $0.sessionID == sessionID })?.segmentID,
               let seg = ScheduleEvaluator.segment(in: lockState.snapshot, id: preferred) {
                return seg
            }
            return session.segments.first { !$0.validated } ?? session.segments.first
        }()
        guard let segment else { return nil }
        return (session, segment)
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else {
                TabView {
                    OverviewView()
                        .tabItem { Label("Overview", systemImage: "house") }
                    CalendarHomeView()
                        .tabItem { Label("Calendar", systemImage: "calendar") }
                    SessionsView()
                        .tabItem { Label("Sessions", systemImage: "clock") }
                    ProgressHomeView()
                        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                    BlocklistsView()
                        .tabItem { Label("Blocklist", systemImage: "hand.raised") }
                    ZonesView()
                        .tabItem { Label("Zones", systemImage: "square.grid.2x2") }
                }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
            }
        }
        .onAppear {
            migrateLegacyOnboarding()
            lockState.refresh(sessions: sessions)
        }
        .onChange(of: sessions.count) { _, _ in lockState.refresh(sessions: sessions) }
        .onChange(of: scheduleToken) { _, _ in lockState.refresh(sessions: sessions) }
        .onReceive(NotificationCenter.default.publisher(for: .lockinBreakEnded)) { note in
            guard let sessionID = note.userInfo?["sessionID"] as? UUID,
                  let started = note.userInfo?["startedAt"] as? Date,
                  let ended = note.userInfo?["endedAt"] as? Date else { return }
            let log = BreakUsageLog()
            log.sessionID = sessionID
            log.startedAt = started
            log.endedAt = ended
            log.note = "Scheduled break"
            context.insert(log)
            try? context.save()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if AppGroup.defaults.bool(forKey: "lockin.openValidation") {
                AppGroup.defaults.set(false, forKey: "lockin.openValidation")
                lockState.openValidation()
            }
            lockState.refresh(sessions: sessions)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .lockinOpenValidation)) { _ in
            lockState.openValidation()
        }
        .task(id: lockState.activePhases.map { $0.sessionID?.uuidString ?? "" }.joined()) {
            await pollXboxIfNeeded()
        }
        .sheet(isPresented: $lockState.showValidation) {
            if let pair = validationPair {
                ValidationView(session: pair.0, segment: pair.1)
            }
        }
    }

    private func pollXboxIfNeeded() async {
        let xboxSessions = lockState.activeSessions.filter { $0.xboxEnabled && !$0.xboxGamertag.isEmpty }
        guard !xboxSessions.isEmpty else { return }
        let interval = TimeInterval(max(5, settings.first?.xboxNudgeIntervalMinutes ?? 15) * 60)
        while !Task.isCancelled {
            if Date().timeIntervalSince(lastXboxPoll) >= min(interval, 60) {
                lastXboxPoll = Date()
                let key = KeychainStore.get(KeychainStore.Key.xboxAPIKey) ?? ""
                for session in xboxSessions {
                    if let presence = await XboxPresenceService().poll(
                        gamertag: session.xboxGamertag,
                        apiKey: key,
                        nudgeMinutes: settings.first?.xboxNudgeIntervalMinutes ?? 15,
                        sessionID: session.id
                    ) {
                        await XboxPresenceService.logPresence(presence, sessionID: session.id, context: context)
                    }
                }
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
