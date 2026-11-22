#if os(macOS)
import SwiftUI
import AppKit

/// Keeps Lockin alive on the Mac while a block is on: closing the window does not quit,
/// and Cmd-Q is refused during a block (except for logout / shutdown, which must work).
final class LockinAppDelegate: NSObject, NSApplicationDelegate {
    private var systemIsShuttingDown = false
    private var powerOffObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.systemIsShuttingDown = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if systemIsShuttingDown { return .terminateNow }
        return AppGroup.defaults.bool(forKey: AppGroup.Key.shieldsActive) ? .terminateCancel : .terminateNow
    }
}

/// Menu bar item: shows lock state at a glance and lets you reopen the window.
struct LockinMenuBarContent: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        Divider()
        Button("Open Lockin") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Quit Lockin") { NSApp.terminate(nil) }
            .disabled(lockState.shieldsShouldBeOn)
    }

    private var statusLine: String {
        switch lockState.phase {
        case .idle: return "No active block"
        case .activeBlock(_, _, let ends):
            return "Blocking until \(DateFormatters.shortTime.string(from: ends))"
        case .onBreak(_, _, let until):
            return "Break until \(DateFormatters.shortTime.string(from: until))"
        case .overrun:
            return "Still locked — validate to unlock"
        }
    }
}
#endif
