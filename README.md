# Lockin

Personal focus app for iPhone and Mac. During an active block, time-wasters cannot be opened and cannot be unblocked from the phone or from Lockin. Unlock is proof of learning or the session clock.

Both platforms are full clients: plan calendar and sessions, validate/unlock, and manage zones and block lists on either device. Changes sync over iCloud (CloudKit) when both are signed into the same Apple ID.

**Tech stack:** Swift, SwiftUI, SwiftData + CloudKit, FamilyControls / ManagedSettings / DeviceActivity, XcodeGen. Quiz generation and grading use an LLM (Anthropic or OpenAI, bring your own key).

## Tabs

- **Overview** — home. Active sessions, plus today and this-week dashboards.
- **Calendar** — day / week / month, scrollable. Shows zone events, milestones, and sessions, colored by zone. Edit or add only when not in an active block.
- **Sessions** — create and inspect study sessions (time, validation, segments, breaks, block list).
- **Progress** — per-course grade tracker. Milestones (assignments, quizzes, exams) carry a date, weight, status, and score. Shows current grade, worst/best case, and the average you need on what's left to hit your target.
- **Blocklist** — named lists of apps, websites, and optional Xbox tracking.
- **Zones** — groups (usually classes) that own calendar items, milestones, materials, and sessions.

Dashboards also exist at **month**, week, session, and zone zoom levels.

## Zones

A zone has a title and color. Check **Class** to add materials:

- Textbook & resources
- Practice quizzes / tests
- Custom named fields

Sessions and calendar events are created inside a zone. Math = blue → all math quizzes, tests, milestones, and sessions render blue.

## Sessions

Max length: **14 days**.

Required:

- Time / date period
- Block list

Optional:

- **Zone** — attach a class/zone for materials and coloring. Without a zone, the session is a plain timed block.
- **Validation** — if on (requires a zone + milestone), unlock only by passing digital proof. If off, unlock when the clock ends.
- **Segments** — split the session into smaller time windows and/or split the milestone. Only an active segment hard-blocks. A week-long session with seven 3-hour days is mostly unblocked; only those 3-hour windows lock.
- **Breaks** — custom (absolute time/date) or repeating (duration + start offset). Must fall inside the session (and segment, if segmented).

Create flow: schedule → period → optional zone → optional milestone → optional segments → optional breaks → block list.

Unsegmented session = blocking for the entire period.

### Overrun (not shift / skip)

There is no mid-block reschedule. If the window ends and validation is not done, **the block continues** until proof or the 14-day session cap. Hockey, etc. does not unlock anything; you just come back still locked.

During an active block you can add to the block list, nothing else. Calendar / session / zone edits are frozen.

## Validation

Digital only. No handwriting / photos. Works on iPhone and Mac.

Question types match tests: multiple choice, true/false, short answer, long answer. MC and T/F are exact. Short/long are graded on the **final answer**; if that is right, the technique is assumed right. After submit, show the solution either way.

Questions are generated from the attached milestone + zone materials. Far ahead of schedule → harder follow-ups (mastery). After a pass: continue into the next segment, or stop until that segment’s next window.

## Blocklists

Each list contains:

- Apps from iPhone (Screen Time picker) and Mac (bundle IDs via file picker)
- Websites — presets (YouTube, Instagram, other socials) plus custom base URLs. Stored and synced, but **not enforced yet** (see [BACKLOG.md](BACKLOG.md)); today only apps are blocked.
- Optional **Xbox** — gamertag for presence, time tracking, and repeating “you’re on during a block” notifications (not a hard console lock)

Never put Phone, Messages, Settings, Maps, or email on a list. Those are never needed as an “emergency unlock” because they are never blocked. Instagram / YouTube / TV / games have no emergency use; they stay locked until proof or the session cap.

During an active block: add-only, never remove.

## Architecture

```
iPhone ── SwiftData + CloudKit ── Mac
   │                                 │
   Screen Time shields               Quit listed Mac apps
```

- **UI & planning** — SwiftUI + SwiftData on iPhone and Mac: zones, calendar, sessions, blocklists, dashboards, validation.
- **Sync** — same iCloud container (`iCloud.com.cadechanyi.lockin`). Calendar, sessions, zones, and block lists sync both ways. LLM/Xbox API keys stay in Keychain per device.
- **Blocking** — FamilyControls + ManagedSettings + DeviceActivity on iPhone. On Mac, Lockin quits selected apps by bundle ID while a block is active (keep the app running or Open at Login). The Mac app is **not sandboxed** (a sandboxed app cannot quit other apps), closes blocked apps the moment they launch, force-quits ones that ignore a polite quit, and refuses Cmd-Q during a block. A menu bar item shows lock state.
- **Unlock** — session clock, or LLM-generated digital quiz on either device.
- **Xbox** — gamertag presence poll + push nudges. Not a console lock.

## Hard lock (iPhone)

Circumvention is closed by splitting control:

1. **Face ID once** — grant Lockin Screen Time access. After that Lockin applies / lifts shields via API. It never uses or stores a Screen Time PIN.
2. **Screen Time passcode** — set in iOS Settings (or a friend sets it). Code is **not** entered into Lockin and **not** stored on the phone. Leave it on all term. Settings still opens; Screen Time cannot be changed without the PIN.
3. **Lockin UI freeze** — during an active block you cannot edit calendar, sessions, zones, or remove from a block list (add-only). Unlock is proof or the 14-day session cap.

You cannot change blocking in Settings (no PIN) or in Lockin (frozen). Lockin is the only control path, and it refuses mid-block.

Requires iOS 26.4+ so “Apps with Screen Time access” is gated by the Screen Time passcode.

Mac onboarding is separate (quit-based blocking + Open at Login) and does not skip iPhone hard-lock setup after sync.

## Progress tracker

Milestones are the single unit for both studying and grading. A milestone belongs to a zone and has a date, kind (assignment, quiz, lab, midterm, final, project, …), weight (% of the course), status (not started / studying / ready / done) and an optional score.

- **Current grade** is the weighted average of graded work only.
- **Worst / on pace / best case** assume zero / the current average / perfect on everything left.
- **Target** (per course, default 80%) gives "you need X% on the remaining Y% of the course", or tells you it is secured or out of reach.
- Weight you have not entered counts as still to be earned, and the app warns when entered weights don't add to 100%.
- Attach a milestone to a session (even one without validation) and its blocked hours show up as study time.
- Scores, status and weights stay editable during a block. Title, date and scope are frozen with the rest of the plan.

## Sync

Calendar, sessions, zones, milestones, grades and block lists live in one SwiftData store mirrored to CloudKit (`iCloud.com.cadechanyi.lockin`). Per-device state (onboarding, Screen Time authorization, login item) is stored locally and never syncs. Each device blocks with its own mechanism but follows the same synced schedule: iPhone shields the apps picked in the Screen Time picker, Mac quits the bundle IDs on the same block list.

**Settings → iCloud sync** shows whether the device is really syncing, the iCloud account state, last send/receive times, and the last error. If a device falls back to a local-only database, Overview shows a banner. Existing database files are never deleted.

CloudKit sync needs the Push Notifications entitlement (`aps-environment`) on both targets and the `remote-notification` background mode on iOS. Without them the other device only sees changes after a relaunch. Both are in `project.yml`.

## Status

Unit tests (19, passing): `xcodebuild -project Lockin.xcodeproj -scheme LockinMac -destination 'platform=macOS' test` (schedule evaluator + grade math). To run them without a provisioned Apple Developer account, add `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`.

Building to a device requires your own Apple Developer team, with the bundle IDs, App Group, and iCloud container in [ENTITLEMENTS.md](ENTITLEMENTS.md) changed to ones you own.

Working in code, **not yet verified on physical devices** (iOS Screen Time shields, DeviceActivity timing, and two-device CloudKit sync can't be tested in a simulator):

- **iOS** scheme `Lockin` — planning UI, Screen Time shields, dashboards, progress tracker, CloudKit sync
- **Mac** scheme `LockinMac` — same UI and tracker; quits selected apps during a block; CloudKit sync with iPhone
- Blocks must be at least 15 minutes (iOS cannot schedule shorter DeviceActivity windows).
- Family Controls (Development) must be enabled on the iOS App IDs. See [ENTITLEMENTS.md](ENTITLEMENTS.md) for the capabilities each App ID needs.
- Quiz validation (needs an Anthropic/OpenAI key in Settings on each device) is functional but not hardened. See [BACKLOG.md](BACKLOG.md).
- Optional OpenXBL key in Settings for Xbox presence
- Both devices must use the same iCloud account for sync

Native macOS has no `FamilyActivityPicker`. Mac blocking quits apps you add by bundle ID. iPhone uses Screen Time shields (Settings-proof with a Screen Time passcode you do not store in Lockin).

Regenerate the Xcode project after editing `project.yml` with `tools/xcodegen/bin/xcodegen generate`.
