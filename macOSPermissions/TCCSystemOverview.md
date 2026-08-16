# 8.1 TCC System Overview

**Deliverable:** markdown summary.

**TCC** stands for **Transparency, Consent, and Control**. It's the macOS
subsystem behind every "*App* would like to access your Camera / Contacts /
Desktop folder" alert, and behind every list in **System Settings → Privacy &
Security**. It's the mechanism that decides whether an app gets at *user data
and user-facing hardware* — and it answers to the user, not to the developer.

## Where TCC sits among the security layers

macOS has three separate gates that get confused with each other:

| Layer | Question it answers | Enforced by |
| --- | --- | --- |
| Gatekeeper / notarization | *Is this app allowed to run at all?* | Signature + notarization ticket, checked at launch |
| App Sandbox | *What may this process touch, by design?* | Entitlements baked into the signature |
| **TCC** | *Has the user agreed to this app touching their private data?* | `tccd` + the TCC databases, at runtime |

They're independent. A properly signed, notarized, sandboxed app still gets
nothing from the camera until TCC says yes — and a user can revoke that consent
at any time without touching the app.

## How it works

- **`tccd`** is the daemon. There are two instances: one per user session, and
  one system-wide.
- Decisions are stored in SQLite databases named `TCC.db`:
  - **User:** `~/Library/Application Support/com.apple.TCC/TCC.db` — per-user
    consents like Contacts, Calendar, Camera.
  - **System:** `/Library/Application Support/com.apple.TCC/TCC.db` — machine-wide
    consents like Accessibility, Full Disk Access, Screen Recording.
- Both are protected by **SIP**. Even as root you can't write them, and you can't
  read them without Full Disk Access. They are not an API — treat them as
  read-only diagnostics at most.

The flow when an app asks for something:

1. App calls the relevant framework API (or simply touches the protected resource).
2. `tccd` looks for an existing decision for that **client** — identified by
   bundle ID *and* code signing identity.
3. If there's no record and the service is promptable, macOS shows the alert,
   using the purpose string from the app's `Info.plist`.
4. The user's answer is written to the database. Every later launch reuses it
   until the user changes it in System Settings or someone runs `tccutil reset`.

## The services

| Service | Settings pane | `tccutil` name | `Info.plist` key | Prompt? |
| --- | --- | --- | --- | --- |
| Camera | Camera | `Camera` | `NSCameraUsageDescription` | Yes |
| Microphone | Microphone | `Microphone` | `NSMicrophoneUsageDescription` | Yes |
| Contacts | Contacts | `AddressBook` | `NSContactsUsageDescription` | Yes |
| Calendar | Calendars | `Calendar` | `NSCalendarsFullAccessUsageDescription` | Yes |
| Reminders | Reminders | `Reminders` | `NSRemindersFullAccessUsageDescription` | Yes |
| Photos | Photos | `Photos` | `NSPhotoLibraryUsageDescription` | Yes |
| Location | Location Services | — (`CoreLocation`) | `NSLocationWhenInUseUsageDescription` | Yes |
| Speech recognition | Speech Recognition | `SpeechRecognition` | `NSSpeechRecognitionUsageDescription` | Yes |
| Automation (Apple Events) | Automation | `AppleEvents` | `NSAppleEventsUsageDescription` | Yes |
| Desktop / Documents / Downloads | Files and Folders | `SystemPolicyDesktopFolder` etc. | `NSDesktopFolderUsageDescription` etc. | Yes |
| Removable / network volumes | Files and Folders | `SystemPolicyRemovableVolumes` | `NSRemovableVolumesUsageDescription` | Yes |
| Screen Recording | Screen & System Audio Recording | `ScreenCapture` | — | Yes, once |
| **Accessibility** | Accessibility | `Accessibility` | — | **No** |
| **Full Disk Access** | Full Disk Access | `SystemPolicyAllFiles` | — | **No** |
| **Input Monitoring** | Input Monitoring | `ListenEvent` | — | Limited |

The bottom three are the ones that shape a product's onboarding: there is no
"Allow" dialog you can trigger. The user has to open System Settings, find the
list, and add or tick your app themselves. The best an app can do is explain
clearly and deep-link:

```swift
// Opens System Settings directly on the Accessibility list
let url = URL(string:
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

For Accessibility specifically, `AXIsProcessTrustedWithOptions` with
`kAXTrustedCheckOptionPrompt` shows a small alert that offers to open Settings —
it still can't grant anything itself.

## Checking status in code

Rather than triggering a request blindly, ask first:

| Service | Check | Request |
| --- | --- | --- |
| Camera / Microphone | `AVCaptureDevice.authorizationStatus(for:)` | `AVCaptureDevice.requestAccess(for:)` |
| Screen Recording | `CGPreflightScreenCaptureAccess()` | `CGRequestScreenCaptureAccess()` |
| Accessibility | `AXIsProcessTrusted()` | prompt-to-Settings only |
| Input Monitoring | `IOHIDCheckAccess(_:)` | `IOHIDRequestAccess(_:)` |
| Contacts | `CNContactStore.authorizationStatus(for:)` | `requestAccess(for:)` |
| Calendar | `EKEventStore.authorizationStatus(for:)` | `requestFullAccessToEvents()` |

**A missing purpose string is a crash, not a denial.** If the app asks for the
camera and `NSCameraUsageDescription` isn't in `Info.plist`, macOS kills the
process. That's deliberate — Apple wants the user to always see a reason.

## Consent is tied to the code signature

TCC records the client's **code signing identity**, not just its path or bundle
ID. Practical consequences:

- Moving or renaming the app doesn't lose consent.
- Re-signing with a different certificate, or shipping an ad-hoc/unsigned build,
  looks like a *different app* — the user gets asked again.
- Local debug builds get re-signed constantly, so during development you'll be
  re-granting permissions far more often than any real user will.
- An attacker can't drop a malicious binary into a trusted app's slot and inherit
  its permissions.

## Managed Macs (MDM / PPPC)

Organisations can pre-approve some of this with a **Privacy Preferences Policy
Control** payload, keyed by bundle ID and code requirement:

| Can be pre-approved by MDM | Cannot |
| --- | --- |
| Accessibility, Full Disk Access, Apple Events, Files and Folders, Input Monitoring | **Camera** and **Microphone** — always require a local user decision |

Screen Recording sits in between: MDM can't silently grant it, but a managed
`ScreenCapture` entry suppresses the periodic re-confirmation that macOS Sequoia
introduced (unmanaged apps get asked to re-confirm screen capture roughly
monthly).

## Debugging and resetting

```bash
tccutil reset Accessibility                      # reset for every app
tccutil reset ScreenCapture com.krisha.HelloApp  # reset one app
tccutil reset All com.krisha.HelloApp            # every service, one app

log stream --predicate 'subsystem == "com.apple.TCC"' --info   # watch decisions live
```

`tccutil` only **resets** — nothing grants permission from the command line, by
design. Some services need the app relaunched (occasionally a logout) before the
change takes effect. The most reliable way to test a first-run experience is a
freshly created user account, since that starts with an empty user database.

## Why this matters for Focus Bear

A focus app that notices which app you're in, nudges you away from distractions,
or records the screen is squarely in TCC territory — Accessibility at minimum,
possibly Screen Recording and Notifications. None of those can be granted by a
dialog the app puts up, which means:

- Onboarding *is* a permissions flow, not an afterthought — explain the value,
  deep-link to the right pane, and detect the grant so the UI can move on.
- The app must degrade gracefully while permission is missing, and re-check
  rather than assuming a one-time grant is permanent.
- Every release signed with a different identity risks resetting users' consent,
  so signing stability is a product concern, not just a build concern.

## What I learned

TCC is best understood as a *consent ledger keyed by code identity*, not a
permissions API. The developer's side is small — declare purpose strings, check
status, ask at a sensible moment, handle denial — and everything else is
deliberately outside the app's control. The design intent is clear once you see
that the sensitive services (Accessibility, Full Disk Access, Input Monitoring)
are precisely the ones an app can't ask for programmatically: those are the ones
malware would want, so Apple forces the user to grant them by hand.

## Sources

- [`tccutil` reference](https://ss64.com/mac/tccutil.html) — SS64
- [macOS TCC: Transparency, Consent, and Control](https://jetforme.org/2023/12/transparency-consent-control/)
- [PPPC and standard users](https://support.addigy.com/hc/en-us/articles/4403549601043-Privacy-Preferences-Policy-Control-PPPC-for-Standard-Users) — Addigy
- [macOS screen recording permissions](https://www.screenify.studio/blog/2026-04-23-macos-screen-recording-permissions)
