import SwiftUI
import SwiftData
import UserNotifications

@main
struct LockinApp: App {
    @StateObject private var lockState = LockState()
    @StateObject private var sync = SyncMonitor()
    private let container = LockinData.makeContainer()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(LockinAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(lockState)
                .environmentObject(sync)
                .task {
                    NotificationService.requestAuthorization()
                    sync.start()
                    lockState.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: .lockinOpenValidation)) { _ in
                    lockState.openValidation()
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        MenuBarExtra {
            LockinMenuBarContent()
                .environmentObject(lockState)
        } label: {
            Image(systemName: lockState.shieldsShouldBeOn ? "lock.fill" : "lock.open")
        }
        #endif
    }
}
