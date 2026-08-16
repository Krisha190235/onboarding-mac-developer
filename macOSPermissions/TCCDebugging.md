# 8.5 TCC Debugging (tccutil)

**Deliverable:** doc listing reset commands.

`tccutil` is the only supported way to touch the TCC databases from the command
line, and it does exactly one thing: **reset**. There is no `grant` — by design,
since a command that could grant permissions would defeat the point of TCC (8.1).

```text
tccutil reset <service> [bundle-id]
```

- With a bundle ID: resets that service for that app only.
- Without one: resets that service for **every** app on the machine.
- `All` as the service: every service for the given app.

## Service names

| `tccutil` service | System Settings pane |
| --- | --- |
| `All` | everything for one app |
| `Accessibility` | Accessibility |
| `AddressBook` | Contacts |
| `AppleEvents` | Automation |
| `Calendar` | Calendars |
| `Camera` | Camera |
| `ListenEvent` | Input Monitoring |
| `MediaLibrary` | Media & Apple Music |
| `Microphone` | Microphone |
| `Photos` | Photos |
| `PostEvent` | (synthetic keyboard/mouse events) |
| `Reminders` | Reminders |
| `ScreenCapture` | Screen & System Audio Recording |
| `SpeechRecognition` | Speech Recognition |
| `SystemPolicyAllFiles` | Full Disk Access |
| `SystemPolicyDesktopFolder` | Files & Folders — Desktop |
| `SystemPolicyDocumentsFolder` | Files & Folders — Documents |
| `SystemPolicyDownloadsFolder` | Files & Folders — Downloads |
| `SystemPolicyNetworkVolumes` | Files & Folders — Network volumes |
| `SystemPolicyRemovableVolumes` | Files & Folders — Removable volumes |
| `Liverpool` | Location Services |

## The commands I actually use

```bash
# One app, one permission — the everyday case
tccutil reset Camera com.krisha.HelloApp
tccutil reset AddressBook com.krisha.HelloApp

# One app, everything it was ever granted
tccutil reset All com.krisha.HelloApp

# System-level services live in the machine database, so they need sudo
sudo tccutil reset Accessibility com.krisha.HelloApp
sudo tccutil reset SystemPolicyAllFiles com.krisha.HelloApp

# Every app on the machine — nuclear, expect to re-grant everything
tccutil reset ScreenCapture
tccutil reset All
```

For the 8.3 AX probe, the client is the **terminal**, not the script:

```bash
sudo tccutil reset Accessibility com.apple.Terminal
```

Some services take effect immediately; others need the app relaunched, and
Accessibility in particular is most reliable if you quit and reopen the app after
resetting.

## Verifying a reset worked

```bash
# Watch macOS make the decision as it happens
log stream --predicate 'subsystem == "com.apple.TCC"' --info

# What has already been decided, from the app's own point of view
#   (AVCaptureDevice.authorizationStatus / CNContactStore.authorizationStatus)
# — see PermissionsView.swift from 8.2, or AXIsProcessTrusted() for Accessibility

# Sandbox denials look different from TCC denials
log stream --predicate 'senderImagePath contains "Sandbox"' --info
```

The distinction matters: a **sandbox** denial means the entitlement is missing and
no prompt will ever appear; a **TCC** denial means the user said no and the answer
is stored. Same symptom in code, opposite fixes.

## Stale and duplicate entries

The messiest part of TCC debugging, and it hits developers far more than users:

- **TCC keys some entries by binary path, not bundle ID.** Debug builds live under
  `~/Library/Developer/Xcode/DerivedData/…`, so every path change leaves another
  entry — which is why System Settings ends up listing the same app several times.
- **Renaming the app** creates new entries and orphans the old ones.
- **If the bundle no longer exists**, `tccutil` refuses to clean up:

  ```console
  % sudo tccutil reset All com.example.MissingApp
  tccutil: No such bundle identifier "com.example.MissingApp": The operation
  couldn't be completed. (OSStatus error -10814.)
  ```

  The row stays in the database and the ghost entry stays in System Settings.
- **Manual removal** in System Settings (select the row, press the **−** button)
  is the practical fix for those ghosts.

Editing `TCC.db` with `sqlite3` works, but requires **disabling SIP** — not worth
it on a work machine, and not something to build a workflow on.

## Getting a genuinely clean first run

Reset isn't always enough, because consent is keyed to the code signing identity
and other state lives outside TCC:

```bash
tccutil reset All com.krisha.HelloApp        # forget consent
rm -rf ~/Library/Containers/com.krisha.HelloApp   # sandboxed app's container
defaults delete com.krisha.HelloApp 2>/dev/null   # preferences
```

The most faithful test is still a **freshly created user account**: it starts with
an empty user TCC database, so the first-run experience is exactly what a real
user sees. Worth doing once before shipping an onboarding flow.

## Quick reference

```bash
tccutil reset Camera com.krisha.HelloApp             # one app, one service
tccutil reset All com.krisha.HelloApp                # one app, all services
sudo tccutil reset Accessibility com.apple.Terminal  # system-level service
tccutil reset ScreenCapture                          # every app (careful)
log stream --predicate 'subsystem == "com.apple.TCC"' --info
```

## What I learned

`tccutil` is deliberately half a tool: it can forget a decision but never make
one, which is the whole security model expressed as a CLI. The practical
difficulty isn't the syntax, it's that developer machines accumulate stale
entries — duplicate DerivedData paths, renamed bundles, orphans that `tccutil`
won't touch because the bundle is gone. Knowing that the database is keyed by
code identity (and sometimes by path) explains all of it, and makes "test on a
fresh user account" the more honest way to check a first-run flow.

## Sources

- [macOS TCC: Transparency, Consent, and Control](https://jetforme.org/2023/12/transparency-consent-control/) — stale entries, the `-10814` error, direct SQLite access
- [`tccutil` reference](https://ss64.com/mac/tccutil.html) — SS64
- [Helping your users reset TCC privacy decisions](https://macblog.org/reset-tcc-privacy/)
