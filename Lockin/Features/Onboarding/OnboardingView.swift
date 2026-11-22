import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import FamilyControls
#endif
#if os(macOS)
import ServiceManagement
#endif

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DeviceSettings.Key.onboardingComplete) private var onboardingComplete = false
    @AppStorage(DeviceSettings.Key.screenTimeAuthorized) private var storedAuthorized = false
    @AppStorage(DeviceSettings.Key.passcodeConfirmed) private var storedPasscodeConfirmed = false
    @AppStorage(DeviceSettings.Key.openAtLogin) private var storedOpenAtLogin = false
    @State private var authorized = false
    @State private var passcodeConfirmed = false
    @State private var versionOK = true
    @State private var understoodMacBlocking = false
    @State private var openAtLogin = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(macOS)
                    macContent
                    #else
                    iosContent
                    #endif

                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red)
                    }

                    Button("Finish setup") { finish() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canFinish)
                        .padding(.top, 8)
                }
                .padding()
            }
            .onAppear {
                #if os(iOS)
                versionOK = isVersionOK()
                authorized = AuthorizationCenter.shared.authorizationStatus == .approved
                #else
                openAtLogin = storedOpenAtLogin
                #endif
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macContent: some View {
        Text("Mac setup")
            .font(.largeTitle.bold())
        Text("Plan sessions, calendar, and unlock here the same as on iPhone. Changes sync over iCloud. During a block, Lockin quits the Mac apps on your block list.")
            .foregroundStyle(.secondary)

        step(1, title: "Mac app blocking", done: understoodMacBlocking) {
            Text("Native macOS cannot use Screen Time’s app picker. Add Mac apps by bundle ID in the Blocklist tab. While a session is active, Lockin quits those apps (keep this app running).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("I understand Mac blocking uses quit-by-app, not iPhone shields", isOn: $understoodMacBlocking)
        }

        step(2, title: "Stay running", done: openAtLogin || understoodMacBlocking) {
            Toggle("Open Lockin at login", isOn: $openAtLogin)
            Text("Recommended so blocks still apply after restart. You can change this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        step(3, title: "API keys", done: true) {
            Text("Add your Anthropic or OpenAI key (and optional Xbox key) in Settings on this Mac. Keys stay on each device and do not sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var iosContent: some View {
        Text("Hard lock setup")
            .font(.largeTitle.bold())
        Text("Lockin can block apps. You keep Settings. Screen Time stays locked with a passcode you do not store here.")
            .foregroundStyle(.secondary)

        step(1, title: "Allow Screen Time", done: authorized) {
            Button(authorized ? "Authorized" : "Authorize with Face ID") {
                Task { await requestAuth() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authorized)
        }

        step(2, title: "iOS 26.4+", done: versionOK) {
            Text(versionOK
                 ? "This device is new enough for Screen Time passcode to gate app access."
                 : "Update iOS. On older versions, Screen Time access can still be turned off with Face ID.")
                .font(.subheadline)
                .foregroundStyle(versionOK ? Color.secondary : Color.orange)
        }

        step(3, title: "Screen Time passcode", done: passcodeConfirmed) {
            Text("Set a Screen Time passcode in iOS Settings. Do not save it on this phone. A friend can set it. Lockin never sees this code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Screen Time settings") { openScreenTimeSettings() }
            Toggle("I set a passcode I do not keep on this phone", isOn: $passcodeConfirmed)
        }
    }
    #endif

    private func step<Content: View>(_ number: Int, title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                Text("\(number). \(title)").font(.headline)
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var canFinish: Bool {
        #if os(macOS)
        understoodMacBlocking
        #else
        authorized && passcodeConfirmed
        #endif
    }

    #if os(iOS)
    private func requestAuth() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            storedAuthorized = authorized
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openScreenTimeSettings() {
        if let url = URL(string: "App-Prefs:SCREEN_TIME") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func isVersionOK() -> Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.majorVersion > 26 { return true }
        if v.majorVersion == 26 { return v.minorVersion >= 4 }
        return false
    }
    #endif

    private func finish() {
        #if os(macOS)
        storedOpenAtLogin = openAtLogin
        setLoginItem(openAtLogin)
        #else
        storedAuthorized = authorized
        storedPasscodeConfirmed = passcodeConfirmed
        #endif
        onboardingComplete = true
        dismiss()
    }

    #if os(macOS)
    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Toggle still stored; user can retry in Settings.
        }
    }
    #endif
}
