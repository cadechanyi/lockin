import Foundation
import SwiftUI
import CoreData
import CloudKit
import Combine

/// Surfaces what CloudKit sync is actually doing so "it doesn't sync" is diagnosable on
/// device instead of silent. SwiftData is backed by `NSPersistentCloudKitContainer`, which
/// posts an event notification for every setup / import / export.
@MainActor
final class SyncMonitor: ObservableObject {
    @Published private(set) var mode: StoreMode = LockinData.mode
    @Published private(set) var accountStatus: String = "Checking…"
    @Published private(set) var accountAvailable = false
    @Published private(set) var lastImport: Date?
    @Published private(set) var lastExport: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var inFlight = false

    private var observer: NSObjectProtocol?

    func start() {
        mode = LockinData.mode
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in self?.handle(event) }
        }
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        // Only touch CloudKit when the store really is CloudKit-backed; building a CKContainer
        // on a binary without the iCloud entitlement raises an Objective-C exception.
        guard LockinData.mode.isSyncing else {
            accountStatus = "Not using iCloud"
            accountAvailable = false
            return
        }
        do {
            let status = try await CKContainer(identifier: LockinData.cloudKitContainerID).accountStatus()
            switch status {
            case .available:
                accountStatus = "Signed in"
                accountAvailable = true
            case .noAccount:
                accountStatus = "Not signed in to iCloud"
                accountAvailable = false
            case .restricted:
                accountStatus = "iCloud restricted on this device"
                accountAvailable = false
            case .couldNotDetermine:
                accountStatus = "Could not determine"
                accountAvailable = false
            case .temporarilyUnavailable:
                accountStatus = "Temporarily unavailable"
                accountAvailable = false
            @unknown default:
                accountStatus = "Unknown"
                accountAvailable = false
            }
        } catch {
            accountStatus = "Error: \(error.localizedDescription)"
            accountAvailable = false
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            inFlight = true
            return
        }
        inFlight = false
        if let error = event.error {
            lastError = error.localizedDescription
            return
        }
        guard event.succeeded else { return }
        lastError = nil
        switch event.type {
        case .import: lastImport = event.endDate
        case .export: lastExport = event.endDate
        default: break
        }
    }
}
