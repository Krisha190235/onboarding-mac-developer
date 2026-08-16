# 8.4 Sandbox Entitlements

**Deliverable:** entitlements file + explanation.

The entitlements file: `XcodeDeepDive/HelloApp/HelloApp/HelloApp.entitlements`,
wired into the target with `CODE_SIGN_ENTITLEMENTS = HelloApp/HelloApp.entitlements`.
Every key in it is annotated in place; this note explains the model around it.

## What the App Sandbox actually is

A sandboxed app runs inside a **container** — `~/Library/Containers/<bundle-id>/Data`
— which the app sees as its home directory. Inside the container it can do what
it likes. Outside it, the answer is **no** by default: no arbitrary file access,
no network, no camera, no other app's data.

Entitlements are how you buy back specific capabilities. They're a plist of keys
compiled into the code signature, so they can't be edited after signing without
breaking it. The sandbox is **mandatory for the Mac App Store** and optional (but
recommended) for Developer ID distribution.

The three layers, which are easy to conflate:

| | Decided by | Checked when | Can the user change it? |
| --- | --- | --- | --- |
| **Sandbox entitlements** | The developer, at build time | Every syscall, by the kernel | No |
| **Hardened runtime** | The developer, at build time | Process launch and runtime | No |
| **TCC consent** | The user, at runtime | First access to protected data | Yes, any time |

For something like the camera, the sandbox entitlement and the TCC prompt are
*both* required — the entitlement says "this app is allowed to be asked", TCC
records what the user answered.

## HelloApp's entitlements, key by key

| Key | Why it's here |
| --- | --- |
| `com.apple.security.app-sandbox` | Turns the sandbox on. Without it the rest of the file does nothing. |
| `com.apple.security.files.user-selected.read-only` | Lets the app read files the user explicitly picks in an open panel. |
| `com.apple.security.device.camera` | 8.2 camera demo — the sandbox must allow the hardware before TCC will even prompt. |
| `com.apple.security.personal-information.addressbook` | 8.2 Contacts demo, paired with `NSContactsUsageDescription`. |

Four keys, four justifications. The file also carries a commented list of the
entitlements deliberately **not** requested, which is the part I'd want in a real
codebase — it documents that the omissions are decisions, not oversights.

## Common entitlements to choose from

```xml
<!-- Network -->
<key>com.apple.security.network.client</key><true/>   <!-- outgoing -->
<key>com.apple.security.network.server</key><true/>   <!-- listening -->

<!-- Files -->
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
<key>com.apple.security.files.bookmarks.app-scope</key><true/>

<!-- Hardware -->
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.device.usb</key><true/>
<key>com.apple.security.print</key><true/>

<!-- Personal data -->
<key>com.apple.security.personal-information.addressbook</key><true/>
<key>com.apple.security.personal-information.calendars</key><true/>
<key>com.apple.security.personal-information.location</key><true/>

<!-- Sharing with helpers, XPC services and extensions -->
<key>com.apple.security.application-groups</key>
<array><string>TEAMID.com.krisha.HelloApp</string></array>
<key>com.apple.security.inherit</key><true/>
```

## Powerbox and security-scoped bookmarks

The `files.user-selected` entitlements don't grant a folder — they grant whatever
the *user* chooses in a standard `NSOpenPanel` or `NSSavePanel`. That panel runs
outside the app in a system process (**Powerbox**), which is why the app can't
fake a selection: the app never draws the picker, it only receives the result.

That grant lasts for the life of the process. To keep access across launches the
app has to create a **security-scoped bookmark** (requires
`com.apple.security.files.bookmarks.app-scope`) and bracket use with
`startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
Without that, a "remembered" file path silently fails to open next launch — a
classic sandbox bug, because the path is still valid, just not permitted.

## Temporary exceptions

Apple provides `com.apple.security.temporary-exception.*` keys for cases the
normal entitlements don't cover — absolute paths, Apple Events to a named app,
and similar. They work, but on the App Store each one has to be justified in the
**App Sandbox Entitlement Usage Information** section at submission, and review
pushes back on them. Treat them as evidence the design needs rethinking, not as a
shortcut.

## Verifying what actually shipped

```bash
# what the signature really contains — the only source of truth
codesign -d --entitlements :- HelloApp.app

# is the sandbox on? (look for the sandbox flag / container)
codesign -dvvv HelloApp.app
ls ~/Library/Containers/com.krisha.HelloApp/Data

# watch denials as they happen
log stream --predicate 'senderImagePath contains "Sandbox"' --info
```

A sandbox denial shows up in the log as `deny(1) file-read-data` (or similar) and
in code as an ordinary "no such file" or permission error — the API doesn't tell
you the sandbox is the reason, which is what makes these bugs slow to spot.

Two gotchas worth remembering:

- **`bplist00` in the entitlements output** means a binary plist got embedded;
  notarization rejects that. Keep the file ASCII XML (`plutil -lint` checks it).
- **Adding an entitlement doesn't retroactively fix a running app.** Rebuild,
  re-sign, and relaunch — and if the container is in a weird state, deleting
  `~/Library/Containers/<bundle-id>` gives a clean first-run.

## What I learned

Entitlements are the answer to "what is this app allowed to *ask* for", which is
a different question from "what has the user agreed to". Writing the file by hand
made the least-privilege point concrete: every key is a permanent widening of the
sandbox that ships in the signature and gets read by App Review, so the useful
discipline is being able to justify each line — and to write down why the others
are missing.

## Sources

- [App Sandbox temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) — Apple
- [App Sandbox information at submission](https://www.developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information) — App Store Connect Help
- [What are app entitlements, and what do they do?](https://eclecticlight.co/2025/03/24/what-are-app-entitlements-and-what-do-they-do/) — The Eclectic Light Company
