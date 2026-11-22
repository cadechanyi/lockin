import Foundation

#if os(macOS)
import AppKit

/// Quits the Mac apps on the active block list for as long as a block is on.
///
/// Requires Lockin to be running and NOT sandboxed (a sandboxed app cannot quit other
/// apps). Three layers: an immediate sweep, a launch observer so a blocked app closes the
/// moment it opens, and a periodic sweep as a backstop. Apps that ignore a polite quit
/// (e.g. an "unsaved changes" sheet) are force-quit after a short grace period.
final class MacAppBlocker {
    static let shared = MacAppBlocker()

    /// Never terminate these even if somehow listed.
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.WindowServer"
    ]
    private static let forceQuitAfter: TimeInterval = 3

    private var timer: Timer?
    private var launchObserver: NSObjectProtocol?
    private var askedAt: [pid_t: Date] = [:]

    private init() {}

    var isEnforcing: Bool { timer != nil }

    func enforce() {
        DispatchQueue.main.async {
            self.sweep()
            if self.timer == nil {
                self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    self?.sweep()
                }
            }
            if self.launchObserver == nil {
                self.launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didLaunchApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    self?.quitIfBlocked(app)
                }
            }
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            if let observer = self.launchObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                self.launchObserver = nil
            }
            self.askedAt.removeAll()
        }
    }

    private var blockedIDs: Set<String> {
        Set(AppGroup.defaults.stringArray(forKey: AppGroup.Key.macBundleIDs) ?? [])
            .subtracting(Self.protectedBundleIDs)
    }

    private func sweep() {
        let ids = blockedIDs
        guard !ids.isEmpty else { return }
        let running = NSWorkspace.shared.runningApplications
        let livePIDs = Set(running.map(\.processIdentifier))
        askedAt = askedAt.filter { livePIDs.contains($0.key) }
        for app in running {
            guard let bundleID = app.bundleIdentifier, ids.contains(bundleID) else { continue }
            quit(app)
        }
    }

    private func quitIfBlocked(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, blockedIDs.contains(bundleID) else { return }
        quit(app)
    }

    private func quit(_ app: NSRunningApplication) {
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let pid = app.processIdentifier
        if let asked = askedAt[pid] {
            if Date().timeIntervalSince(asked) >= Self.forceQuitAfter {
                app.forceTerminate()
            }
        } else {
            askedAt[pid] = Date()
            app.terminate()
        }
    }
}
#endif
