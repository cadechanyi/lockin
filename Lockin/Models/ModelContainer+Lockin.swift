import Foundation
import SwiftData
#if os(macOS)
import Security
#endif

/// Which store the app actually opened. Shown in Settings so a silent fall-back to a
/// local-only store (the usual reason two devices "don't sync") is never invisible.
enum StoreMode: Equatable {
    case cloudKit
    case localOnly(reason: String)
    case memoryOnly(reason: String)

    var isSyncing: Bool { self == .cloudKit }
}

enum LockinData {
    static let cloudKitContainerID = "iCloud.com.cadechanyi.lockin"
    private static let cloudStoreName = "Lockin"
    private static let localStoreName = "LockinLocal"
    private static let importFlagKey = "lockin.didImportLocalToCloudKit"

    /// Set once by `makeContainer()`.
    private(set) static var mode: StoreMode = .cloudKit

    static var schema: Schema {
        Schema([
            Zone.self,
            Milestone.self,
            CalendarEvent.self,
            Blocklist.self,
            StudySession.self,
            SessionSegment.self,
            BreakWindow.self,
            AppSettings.self,
            BreakUsageLog.self,
            XboxPresenceLog.self,
            ValidationAttempt.self
        ])
    }

    /// CloudKit-backed store shared by iPhone and Mac (same iCloud container).
    /// If CloudKit cannot open, falls back to an on-device store and records why in
    /// `mode`. Existing store files are never deleted.
    static func makeContainer() -> ModelContainer {
        let cloudAttempt: Result<ModelContainer, StoreError>
        if let blocked = cloudKitUnavailableReason() {
            cloudAttempt = .failure(StoreError(message: blocked))
        } else {
            cloudAttempt = tryCreate(named: cloudStoreName, cloudKit: true)
        }
        switch cloudAttempt {
        case .success(let container):
            mode = .cloudKit
            importFromLocalIfNeeded(into: container)
            return container
        case .failure(let cloudError):
            let reason = cloudError.message
            if case .success(let container) = tryCreate(named: localStoreName, cloudKit: false) {
                mode = .localOnly(reason: reason)
                return container
            }
            // Local store unreadable too: set it aside (kept as a backup, never deleted).
            moveAside(named: localStoreName)
            if case .success(let container) = tryCreate(named: localStoreName, cloudKit: false) {
                mode = .localOnly(reason: reason)
                return container
            }
            mode = .memoryOnly(reason: reason)
            let memory = ModelConfiguration(
                "LockinMemory",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Lockin could not open its database: \(error)")
            }
        }
    }

    /// Opening a CloudKit-backed store in a binary that lacks the iCloud entitlement does not
    /// fail cleanly: container creation "succeeds", then CloudKit setup aborts the process on a
    /// background queue. So check up front (macOS can read its own entitlements; on iOS,
    /// Xcode signing always embeds them).
    private static func cloudKitUnavailableReason() -> String? {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-container-identifiers" as CFString, nil
              ) as? [String],
              value.contains(cloudKitContainerID) else {
            return "This Mac build is not signed with the iCloud (CloudKit) entitlement for \(cloudKitContainerID). In Xcode: select the LockinMac target → Signing & Capabilities → pick your team, and make sure iCloud → CloudKit and that container are enabled."
        }
        #endif
        return nil
    }

    private static func tryCreate(named name: String, cloudKit: Bool) -> Result<ModelContainer, StoreError> {
        let config = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKit ? .private(cloudKitContainerID) : .none
        )
        do {
            return .success(try ModelContainer(for: schema, configurations: [config]))
        } catch {
            print("LockinData: failed to open store \(name) cloudKit=\(cloudKit): \(error)")
            return .failure(StoreError(message: String(describing: error)))
        }
    }

    /// Renames `<name>.store*` files so they can be recovered by hand. Never deletes.
    private static func moveAside(named name: String) {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let contents = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) else {
            return
        }
        let stamp = Int(Date().timeIntervalSince1970)
        for url in contents where url.lastPathComponent.hasPrefix("\(name).store") {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).\(stamp).moved-aside")
            try? fm.moveItem(at: url, to: backup)
        }
    }

    // MARK: - One-shot LockinLocal → CloudKit import

    private static func importFromLocalIfNeeded(into cloud: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: importFlagKey) else { return }

        let cloudContext = ModelContext(cloud)
        let cloudHasData =
            ((try? cloudContext.fetchCount(FetchDescriptor<Zone>())) ?? 0) > 0
            || ((try? cloudContext.fetchCount(FetchDescriptor<StudySession>())) ?? 0) > 0
            || ((try? cloudContext.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0) > 0
            || ((try? cloudContext.fetchCount(FetchDescriptor<Blocklist>())) ?? 0) > 0

        if cloudHasData {
            defaults.set(true, forKey: importFlagKey)
            return
        }

        guard case .success(let local) = tryCreate(named: localStoreName, cloudKit: false) else {
            defaults.set(true, forKey: importFlagKey)
            return
        }

        let localContext = ModelContext(local)
        let localHasData =
            ((try? localContext.fetchCount(FetchDescriptor<Zone>())) ?? 0) > 0
            || ((try? localContext.fetchCount(FetchDescriptor<StudySession>())) ?? 0) > 0
            || ((try? localContext.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0) > 0
            || ((try? localContext.fetchCount(FetchDescriptor<Blocklist>())) ?? 0) > 0

        guard localHasData else {
            defaults.set(true, forKey: importFlagKey)
            return
        }

        do {
            try copyAll(from: localContext, to: cloudContext)
            try cloudContext.save()
            defaults.set(true, forKey: importFlagKey)
            print("LockinData: imported LockinLocal into CloudKit store")
        } catch {
            print("LockinData: local→CloudKit import failed: \(error)")
        }
    }

    private static func copyAll(from local: ModelContext, to cloud: ModelContext) throws {
        var blocklistByID: [UUID: Blocklist] = [:]
        for old in try local.fetch(FetchDescriptor<Blocklist>()) {
            let copy = Blocklist(name: old.name)
            copy.id = old.id
            copy.familyActivitySelectionData = old.familyActivitySelectionData
            copy.macFamilyActivitySelectionData = old.macFamilyActivitySelectionData
            copy.websitePresetsJSON = old.websitePresetsJSON
            copy.customWebsitesJSON = old.customWebsitesJSON
            copy.xboxEnabled = old.xboxEnabled
            copy.xboxGamertag = old.xboxGamertag
            copy.macBundleIDsJSON = old.macBundleIDsJSON
            copy.createdAt = old.createdAt
            cloud.insert(copy)
            blocklistByID[copy.id] = copy
        }

        var zoneByID: [UUID: Zone] = [:]
        for old in try local.fetch(FetchDescriptor<Zone>()) {
            let copy = Zone(title: old.title, colorHex: old.colorHex, isClass: old.isClass)
            copy.id = old.id
            copy.textbookResources = old.textbookResources
            copy.practiceQuizzes = old.practiceQuizzes
            copy.customMaterialsJSON = old.customMaterialsJSON
            copy.createdAt = old.createdAt
            copy.targetGrade = old.targetGrade
            cloud.insert(copy)
            zoneByID[copy.id] = copy
        }

        var milestoneByID: [UUID: Milestone] = [:]
        for old in try local.fetch(FetchDescriptor<Milestone>()) {
            let zone = old.zone.flatMap { zoneByID[$0.id] }
            let copy = Milestone(
                title: old.title,
                scope: old.scope,
                kind: old.kind,
                startDate: old.startDate,
                zone: zone
            )
            copy.id = old.id
            copy.createdAt = old.createdAt
            copy.weight = old.weight
            copy.scoreEarned = old.scoreEarned
            copy.scoreMax = old.scoreMax
            copy.statusRaw = old.statusRaw
            copy.notes = old.notes
            cloud.insert(copy)
            milestoneByID[copy.id] = copy
        }

        for old in try local.fetch(FetchDescriptor<CalendarEvent>()) {
            let zone = old.zone.flatMap { zoneByID[$0.id] }
            let copy = CalendarEvent(
                title: old.title,
                kind: old.kind,
                startDate: old.startDate,
                endDate: old.endDate,
                zone: zone
            )
            copy.id = old.id
            copy.allDay = old.allDay
            cloud.insert(copy)
        }

        for old in try local.fetch(FetchDescriptor<StudySession>()) {
            let copy = StudySession()
            copy.id = old.id
            copy.title = old.title
            copy.startDate = old.startDate
            copy.endDate = old.endDate
            copy.validationEnabled = old.validationEnabled
            copy.isSegmented = old.isSegmented
            copy.createdAt = old.createdAt
            copy.zone = old.zone.flatMap { zoneByID[$0.id] }
            copy.milestone = old.milestone.flatMap { milestoneByID[$0.id] }
            copy.blocklist = old.blocklist.flatMap { blocklistByID[$0.id] }
            cloud.insert(copy)

            for seg in old.segments ?? [] {
                let s = SessionSegment()
                s.id = seg.id
                s.startDate = seg.startDate
                s.endDate = seg.endDate
                s.milestoneSubset = seg.milestoneSubset
                s.validatedAt = seg.validatedAt
                s.session = copy
                cloud.insert(s)
            }
            for brk in old.breaks ?? [] {
                let b = BreakWindow()
                b.id = brk.id
                b.kindRaw = brk.kindRaw
                b.startDate = brk.startDate
                b.endDate = brk.endDate
                b.durationMinutes = brk.durationMinutes
                b.intervalMinutes = brk.intervalMinutes
                b.offsetMinutes = brk.offsetMinutes
                b.segmentID = brk.segmentID
                b.session = copy
                cloud.insert(b)
            }
        }

        for old in try local.fetch(FetchDescriptor<AppSettings>()) {
            let copy = AppSettings()
            copy.id = old.id
            copy.screenTimeAuthorized = old.screenTimeAuthorized
            copy.screenTimePasscodeConfirmed = old.screenTimePasscodeConfirmed
            copy.onboardingComplete = old.onboardingComplete
            copy.macOnboardingComplete = old.macOnboardingComplete
            copy.macScreenTimeAuthorized = old.macScreenTimeAuthorized
            copy.xboxNudgeIntervalMinutes = old.xboxNudgeIntervalMinutes
            copy.llmProviderRaw = old.llmProviderRaw
            copy.openAtLogin = old.openAtLogin
            cloud.insert(copy)
        }

        for old in try local.fetch(FetchDescriptor<BreakUsageLog>()) {
            let copy = BreakUsageLog()
            copy.id = old.id
            copy.startedAt = old.startedAt
            copy.endedAt = old.endedAt
            copy.sessionID = old.sessionID
            copy.note = old.note
            cloud.insert(copy)
        }

        for old in try local.fetch(FetchDescriptor<XboxPresenceLog>()) {
            let copy = XboxPresenceLog()
            copy.id = old.id
            copy.timestamp = old.timestamp
            copy.gamertag = old.gamertag
            copy.isPlaying = old.isPlaying
            copy.titleName = old.titleName
            copy.sessionID = old.sessionID
            cloud.insert(copy)
        }

        for old in try local.fetch(FetchDescriptor<ValidationAttempt>()) {
            let copy = ValidationAttempt()
            copy.id = old.id
            copy.timestamp = old.timestamp
            copy.sessionID = old.sessionID
            copy.segmentID = old.segmentID
            copy.passed = old.passed
            copy.mastery = old.mastery
            copy.questionKind = old.questionKind
            cloud.insert(copy)
        }
    }
}

struct StoreError: Error, Equatable {
    var message: String
}
