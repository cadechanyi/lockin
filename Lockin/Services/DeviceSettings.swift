import Foundation

/// State that belongs to *this device only* and must never sync over iCloud.
/// Use with `@AppStorage(DeviceSettings.Key.…)` in views.
enum DeviceSettings {
    enum Key {
        static let onboardingComplete = "device.onboardingComplete"
        static let screenTimeAuthorized = "device.screenTimeAuthorized"
        static let passcodeConfirmed = "device.screenTimePasscodeConfirmed"
        static let openAtLogin = "device.openAtLogin"
    }
}
