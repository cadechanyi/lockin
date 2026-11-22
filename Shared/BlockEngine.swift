import Foundation

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#if os(iOS)
import DeviceActivity
#endif
#endif

enum BlockEngine {
    static let storeName = "lockin.block"

    static func persistSelection(_ data: Data?, mac: Bool = false) {
        let url = mac ? AppGroup.macSelectionURL : AppGroup.selectionURL
        if let data {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        AppGroup.defaults.set(data, forKey: mac ? AppGroup.Key.macSelectionData : AppGroup.Key.selectionData)
    }

    static func loadSelectionData(mac: Bool = false) -> Data? {
        let url = mac ? AppGroup.macSelectionURL : AppGroup.selectionURL
        if let data = try? Data(contentsOf: url) { return data }
        return AppGroup.defaults.data(forKey: mac ? AppGroup.Key.macSelectionData : AppGroup.Key.selectionData)
    }

    static func persist(snapshot: ScheduleSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: AppGroup.snapshotURL, options: .atomic)
            AppGroup.defaults.set(data, forKey: AppGroup.Key.snapshot)
        }

        let phases = ScheduleEvaluator.evaluateAll(snapshot: snapshot)
        let shielding = phases.filter(\.shieldsShouldBeOn)
        let primary = ScheduleEvaluator.evaluate(snapshot: snapshot)

        AppGroup.defaults.set(!shielding.isEmpty, forKey: AppGroup.Key.shieldsActive)

        let shieldingSessions = shielding.compactMap { phase -> SessionSnapshot? in
            guard let id = phase.sessionID else { return nil }
            return ScheduleEvaluator.session(in: snapshot, id: id)
        }

        if shieldingSessions.isEmpty {
            AppGroup.defaults.set(false, forKey: AppGroup.Key.validationRequired)
            AppGroup.defaults.set([], forKey: AppGroup.Key.macBundleIDs)
        } else {
            let anyValidation = shieldingSessions.contains(where: \.validationEnabled)
            AppGroup.defaults.set(anyValidation, forKey: AppGroup.Key.validationRequired)
            let latestCap = shieldingSessions.map(\.capDate).max() ?? Date()
            AppGroup.defaults.set(latestCap.timeIntervalSince1970, forKey: AppGroup.Key.sessionCap)

            let xboxSession = shieldingSessions.first(where: { $0.xboxEnabled && !$0.xboxGamertag.isEmpty })
            AppGroup.defaults.set(xboxSession?.xboxGamertag ?? "", forKey: AppGroup.Key.xboxGamertag)
            AppGroup.defaults.set(xboxSession != nil, forKey: "lockin.xboxEnabled")

            let macIDs = Array(Set(shieldingSessions.flatMap(\.macBundleIDs))).sorted()
            AppGroup.defaults.set(macIDs, forKey: AppGroup.Key.macBundleIDs)

            #if os(iOS) && canImport(FamilyControls)
            if let merged = mergeFamilySelections(shieldingSessions.compactMap(\.familyActivitySelectionData)) {
                persistSelection(merged, mac: false)
            }
            #endif
        }

        if case .onBreak(_, _, let until) = primary, shielding.isEmpty {
            AppGroup.defaults.set(until.timeIntervalSince1970, forKey: AppGroup.Key.onBreakUntil)
        } else {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.onBreakUntil)
        }
        if phases.contains(where: {
            if case .overrun = $0 { return true }
            return false
        }) {
            AppGroup.defaults.set(false, forKey: AppGroup.Key.validated)
        }
    }

    static func loadSnapshot() -> ScheduleSnapshot? {
        if let data = try? Data(contentsOf: AppGroup.snapshotURL),
           let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
            return snapshot
        }
        if let data = AppGroup.defaults.data(forKey: AppGroup.Key.snapshot),
           let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    static func applyShieldsIfNeeded(now: Date = Date()) {
        guard let snapshot = loadSnapshot() else {
            clearShields()
            return
        }
        persist(snapshot: snapshot)
        let phases = ScheduleEvaluator.evaluateAll(snapshot: snapshot, now: now)
        if phases.contains(where: \.shieldsShouldBeOn) {
            applyShields()
        } else {
            clearShields()
        }
    }

    static func applyShields() {
        #if os(iOS) && canImport(FamilyControls)
        if let data = loadSelectionData(mac: false),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            let store = ManagedSettingsStore(named: .init(storeName))
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
            store.application.denyAppRemoval = true
        }
        #endif
        #if os(macOS)
        MacAppBlocker.shared.enforce()
        #endif
        AppGroup.defaults.set(true, forKey: AppGroup.Key.shieldsActive)
    }

    static func clearShields() {
        #if os(iOS) && canImport(FamilyControls)
        let store = ManagedSettingsStore(named: .init(storeName))
        store.clearAllSettings()
        #endif
        #if os(macOS)
        MacAppBlocker.shared.stop()
        #endif
        AppGroup.defaults.set(false, forKey: AppGroup.Key.shieldsActive)
    }

    #if os(iOS) && canImport(FamilyControls)
    private static func mergeFamilySelections(_ payloads: [Data]) -> Data? {
        guard !payloads.isEmpty else { return nil }
        var merged = FamilyActivitySelection()
        for data in payloads {
            guard let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { continue }
            merged.applicationTokens.formUnion(selection.applicationTokens)
            merged.categoryTokens.formUnion(selection.categoryTokens)
            merged.webDomainTokens.formUnion(selection.webDomainTokens)
        }
        return try? JSONEncoder().encode(merged)
    }
    #endif

    #if os(iOS) && canImport(FamilyControls)
    static func startMonitoring(snapshot: ScheduleSnapshot) {
        let center = DeviceActivityCenter()
        center.stopMonitoring()
        var activities: [DeviceActivityName: DeviceActivitySchedule] = [:]
        let calendar = Calendar.current
        for session in snapshot.sessions {
            for segment in session.segments where !segment.validated {
                let name = DeviceActivityName(LockinActivity.blockName(for: segment.id))
                activities[name] = DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents([.hour, .minute, .month, .day, .year], from: segment.start),
                    intervalEnd: calendar.dateComponents([.hour, .minute, .month, .day, .year], from: segment.end),
                    repeats: false
                )
            }
            for item in session.breaks where item.kind == "custom" {
                guard let start = item.startDate, let end = item.endDate else { continue }
                let name = DeviceActivityName(LockinActivity.breakName(for: item.id))
                activities[name] = DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents([.hour, .minute, .month, .day, .year], from: start),
                    intervalEnd: calendar.dateComponents([.hour, .minute, .month, .day, .year], from: end),
                    repeats: false
                )
            }
        }
        for (name, schedule) in activities {
            try? center.startMonitoring(name, during: schedule)
        }
    }
    #endif
}
