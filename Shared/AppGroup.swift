import Foundation

enum AppGroup {
    static let id = "group.com.cadechanyi.lockin"

    /// iOS shares state with its extensions through the app group. The Mac app has no
    /// extensions (and no app-group entitlement), so it just uses its own defaults.
    static var defaults: UserDefaults {
        #if os(macOS)
        return .standard
        #else
        return UserDefaults(suiteName: id) ?? .standard
        #endif
    }

    static var containerURL: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Lockin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
        #endif
    }

    enum Key {
        static let snapshot = "lockin.scheduleSnapshot"
        static let validationRequired = "lockin.validationRequired"
        static let validated = "lockin.validated"
        static let sessionCap = "lockin.sessionCap"
        static let onBreakUntil = "lockin.onBreakUntil"
        static let selectionData = "lockin.selectionData"
        static let macSelectionData = "lockin.macSelectionData"
        static let shieldsActive = "lockin.shieldsActive"
        static let xboxGamertag = "lockin.xboxGamertag"
        static let xboxNudgeMinutes = "lockin.xboxNudgeMinutes"
        static let lastXboxNudge = "lockin.lastXboxNudge"
        static let macBundleIDs = "lockin.macBundleIDs"
    }

    static var snapshotURL: URL { containerURL.appendingPathComponent("schedule.json") }
    static var selectionURL: URL { containerURL.appendingPathComponent("selection.dat") }
    static var macSelectionURL: URL { containerURL.appendingPathComponent("mac-selection.dat") }
}
