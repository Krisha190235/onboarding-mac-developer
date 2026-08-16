# 8.6 Info.plist Permission Keys

**Deliverable:** sample project with permission prompts.

The sample is `HelloApp`, which now asks for **three** TCC-protected permissions
from its **Permissions…** sheet, each driven by an `Info.plist` purpose string:

| Permission | Purpose-string key | Sandbox entitlement |
| --- | --- | --- |
| Camera | `NSCameraUsageDescription` | `com.apple.security.device.camera` |
| Microphone | `NSMicrophoneUsageDescription` | `com.apple.security.device.audio-input` |
| Contacts | `NSContactsUsageDescription` | `com.apple.security.personal-information.addressbook` |

Code: `XcodeDeepDive/HelloApp/HelloApp/PermissionsView.swift` ·
Entitlements: `XcodeDeepDive/HelloApp/HelloApp/HelloApp.entitlements`

## What a purpose string is for

The string isn't documentation for other developers — it's the sentence macOS
puts in the alert, under the app's name. It's the user's only information when
deciding, so it belongs to the product, not to the plumbing.

Two hard rules:

1. **Missing string = crash.** If the app requests a protected resource without
   the matching key, macOS terminates the process at the moment it asks. Not a
   denial, not a `nil` — a hard stop, so the developer can't ship a silent grab.
2. **The string is baked in at build time.** It can't be changed at runtime, and
   it ships in the bundle where anyone can read it.

## Where the keys live in this project

`HelloApp` sets `GENERATE_INFOPLIST_FILE = YES`, so there is no `Info.plist` file
to edit — Xcode synthesises one during the build from `INFOPLIST_KEY_*` build
settings. The purpose strings are therefore in `project.pbxproj`, on both the
Debug and Release configurations:

```text
INFOPLIST_KEY_NSCameraUsageDescription     = "HelloApp asks for camera access only to
                                              demonstrate how macOS permission prompts
                                              work. Nothing is recorded."
INFOPLIST_KEY_NSMicrophoneUsageDescription = "HelloApp asks for microphone access only
                                              to name the audio input device, as a
                                              permissions demo. No audio is captured
                                              or recorded."
INFOPLIST_KEY_NSContactsUsageDescription   = "HelloApp asks for Contacts access only to
                                              count how many contacts it can see, as a
                                              permissions demo. Nothing is stored or
                                              sent anywhere."
```

Any `Info.plist` key works this way: prefix it with `INFOPLIST_KEY_`. Older
projects with a checked-in `Info.plist` edit the file directly instead — both end
up in the same place in the built bundle.

## The keys worth knowing (macOS)

| Key | Prompt shown for |
| --- | --- |
| `NSCameraUsageDescription` | Camera |
| `NSMicrophoneUsageDescription` | Microphone |
| `NSContactsUsageDescription` | Contacts |
| `NSCalendarsFullAccessUsageDescription` | Calendars (full access) |
| `NSRemindersFullAccessUsageDescription` | Reminders |
| `NSPhotoLibraryUsageDescription` | Photos |
| `NSLocationWhenInUseUsageDescription` | Location |
| `NSSpeechRecognitionUsageDescription` | Speech recognition |
| `NSAppleEventsUsageDescription` | Controlling another app (Automation) |
| `NSDesktopFolderUsageDescription` | Desktop folder |
| `NSDocumentsFolderUsageDescription` | Documents folder |
| `NSDownloadsFolderUsageDescription` | Downloads folder |
| `NSRemovableVolumesUsageDescription` | USB drives, SD cards |
| `NSNetworkVolumesUsageDescription` | Network shares |
| `NSBluetoothAlwaysUsageDescription` | Bluetooth |

Note what's **absent**: Accessibility, Full Disk Access and Input Monitoring have
no purpose-string key, because they have no prompt to put a string in (8.1).
`NSAccessibilityUsageDescription` exists but only affects the nudge dialog, not a
grant.

Calendars and Reminders are worth flagging: the older
`NSCalendarsUsageDescription` was split into full-access and write-only keys on
recent systems, so an app using the old key alone can hit the crash path.

## Writing one that gets approved

App Review rejects vague strings, and users deny them. The pattern that works is
*what* + *why*, in the user's words:

| Weak | Better |
| --- | --- |
| "This app needs camera access." | "HelloApp uses the camera to show you a preview before you start a focus session." |
| "Required for functionality." | "HelloApp reads your contacts so you can pick who to share a session summary with." |
| "For analytics." | Don't — a purpose string that admits to data collection for its own sake is a rejection. |

Mention what you *don't* do when it's reassuring ("nothing is recorded"), and
keep it to one or two sentences: the alert truncates long strings.

## Verifying what actually shipped

```bash
# Every key in the built bundle
plutil -p HelloApp.app/Contents/Info.plist

# Just the purpose strings
plutil -p HelloApp.app/Contents/Info.plist | grep UsageDescription

# And the entitlements that go with them
codesign -d --entitlements :- HelloApp.app
```

Then reset and watch the real alerts appear (8.5):

```bash
tccutil reset All com.krisha.HelloApp
```

If an app crashes the instant it asks for something, the first thing to check is
this list — a typo in a key name is indistinguishable from omitting it.

## What I learned

The purpose string is the one part of the permissions stack that's aimed at the
user rather than the system, and macOS enforces its presence brutally: crash, not
denial. Building it made the three-layer picture concrete — the **entitlement**
says the app may be asked, the **purpose string** is what the user reads while
deciding, and **TCC** stores what they said. Getting the prompt to appear at all
means having all three right, which is why "the prompt never showed" is such a
common bug report.

## Sources

- [Requesting authorization for media capture on macOS](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media) — Apple
- [Protecting the user's privacy](https://developer.apple.com/documentation/uikit/protecting-the-user-s-privacy) — Apple
- [App Store Review Guidelines, 5.1 Privacy](https://developer.apple.com/app-store/review/guidelines/#privacy) — Apple
