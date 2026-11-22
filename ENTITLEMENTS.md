# Family Controls + App IDs

Team ID: `93RYX79RFR`  
Apple Developer: Cade Chanyi

Family Controls (Development) works for local device installs once the capability is enabled on each App ID. Family Controls (Distribution) is required for TestFlight / App Store and must be requested from Apple.

## Bundle IDs

| Target | Bundle ID |
|---|---|
| iOS app | `com.cadechanyi.lockin` |
| macOS app | `com.cadechanyi.lockin.mac` |
| DeviceActivity monitor | `com.cadechanyi.lockin.DeviceActivity` |
| Shield configuration | `com.cadechanyi.lockin.ShieldConfiguration` |
| Shield action | `com.cadechanyi.lockin.ShieldAction` |

App Group (all targets): `group.com.cadechanyi.lockin`  
iCloud container: `iCloud.com.cadechanyi.lockin`

## Developer Portal steps

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → register each App ID above (App + App Clip / App IDs).
2. On the **iOS app and the three iOS extension** App IDs enable:
   - Family Controls (Development) — listed as **Family Controls**
   - App Groups → `group.com.cadechanyi.lockin`
3. On the **iOS app and Mac app** App IDs enable:
   - iCloud (CloudKit) → `iCloud.com.cadechanyi.lockin`
   - **Push Notifications** — required, not optional: CloudKit uses silent pushes to tell the other device something changed. Without it sync only happens on relaunch.
4. The **Mac app needs only iCloud + Push Notifications.** It does not use Family Controls or an App Group, and it is deliberately not sandboxed so it can quit other apps. That means it cannot go on the Mac App Store; run it from Xcode or notarize it for personal use.
5. Create an App Group identifier `group.com.cadechanyi.lockin` if it does not exist.
6. Create an iCloud container `iCloud.com.cadechanyi.lockin`.
7. Regenerate Development provisioning profiles (Xcode Automatic Signing usually does this).

## Distribution entitlement request

Submit **once per bundle ID** (iOS app + every iOS extension; the Mac app does not use Family Controls):

https://developer.apple.com/contact/request/family-controls-distribution

Use this description:

> Lockin is a personal focus app (self-compliance, individual FamilyControls authorization — not a child Apple ID / parental control product). During scheduled study sessions it uses ManagedSettings to shield user-selected distracting apps and websites (Instagram, YouTube, Apple TV, etc.) and DeviceActivity to start/end those shields. Unlock is either the session clock or an in-app knowledge check. The user also sets a system Screen Time passcode they do not store in the app, so Screen Time settings cannot be changed mid-session. ShieldConfiguration/ShieldAction extensions show a lock screen that directs the user back to Lockin. Lockin never frames the Apple ID as a child account.

Request these bundle IDs separately:

1. `com.cadechanyi.lockin`
2. `com.cadechanyi.lockin.DeviceActivity`
3. `com.cadechanyi.lockin.ShieldConfiguration`
4. `com.cadechanyi.lockin.ShieldAction`

After approval, enable **Family Controls (Distribution)** on each App ID and refresh profiles.

## Local testing before distribution approval

Development signing + Family Controls (Development) on the App IDs is enough to run on your iPhone and Mac. Simulator cannot authorize Screen Time.
