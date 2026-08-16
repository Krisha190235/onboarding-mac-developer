# 7.9 Notarization — Summary on Notarization Tools

**Deliverable:** summary on notarization tools.

Notarization is Apple's automated malware scan for Mac software distributed
*outside* the Mac App Store. You upload a signed build, Apple scans it and
checks the signature, and if it passes you get a **ticket** that tells Gatekeeper
the software has been checked. It is **not App Review** — no human looks at it,
and it usually finishes in minutes.

App Store distribution doesn't need it: that submission process already includes
the equivalent checks.

## Why it's mandatory in practice

- macOS 10.14.5+ — software signed with a *new* Developer ID certificate must be
  notarized to run.
- macOS 10.15+ — all Developer ID software built after 1 June 2019 must be
  notarized.
- Without a ticket, Gatekeeper blocks the app on first launch. Since **macOS
  Sequoia (15)** the old Control-click → Open escape hatch is gone; users have to
  go to **System Settings → Privacy & Security → Open Anyway**, which is a
  deliberately awkward path Apple doesn't want normal users taking.

So for a Focus Bear-style app shipped by direct download, notarization isn't
optional — it's the difference between "double-click and it runs" and "macOS says
this app is damaged".

## The tools

| Tool | What it does |
| --- | --- |
| `codesign` | Signs the app with a Developer ID Application certificate, enables the hardened runtime, adds the secure timestamp. Also verifies signatures. |
| `productbuild` / `pkgbuild` / `productsign` | Build and sign installer packages (`.pkg`) with a Developer ID **Installer** certificate. |
| `hdiutil` | Builds the `.dmg` disk image, if that's your distribution format. |
| `ditto` | Zips an `.app` for upload while preserving symlinks and extended attributes — `notarytool` can't take a bare `.app`. |
| **`notarytool`** | Uploads to the Apple notary service, waits for the result, fetches logs and history. The current tool. |
| **`stapler`** | Attaches the returned ticket to the app/dmg/pkg so it validates offline. |
| `spctl` | Asks the *system policy* whether the software would be allowed to run — the closest thing to testing what a user sees. |
| `pkgutil --check-signature` | Verifies installer package signatures. |
| Xcode Organizer | The GUI path: Archive → Distribute App → Developer ID → Upload. Signs, uploads, staples and exports in one flow. |
| Notary API | REST API, for CI systems that don't have Xcode installed. |

### `notarytool` replaced `altool`

Since **1 November 2023** the notary service refuses uploads from `altool` or
Xcode 13 and earlier — `notarytool` (Xcode 13+, use 14+) is the only supported
command-line route. `notarytool` is also dramatically faster, because it uploads
to S3 directly and can wait on the result instead of you polling.

Subcommands: `submit`, `wait`, `info`, `log`, `history`, `store-credentials`.

## Credentials

Two ways to authenticate, both usable with every subcommand:

1. **App Store Connect API key** (recommended) — a `.p8` private key plus key ID,
   and an issuer ID *only* for Team keys. Passing `--issuer` with an Individual
   key returns 401. The private key can only be downloaded once.
2. **Apple ID + app-specific password** + `--team-id`. Simpler to get, but it's a
   password sitting in your CI config.

Either way, store them once so they're not repeated in scripts:

```bash
xcrun notarytool store-credentials "FocusBear-Notary" \
  --key ~/.private_keys/AuthKey_ABCDE12345.p8 \
  --key-id ABCDE12345 \
  --issuer 8a1b2c3d-4e5f-6789-abcd-ef0123456789
```

That writes a keychain item you then reference with `-p "FocusBear-Notary"`. The
profile name is case-sensitive.

## The workflow

```bash
# 1. Sign with Developer ID + hardened runtime + secure timestamp
codesign --force --deep --options runtime --timestamp \
  --entitlements HelloApp.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID1234)" \
  HelloApp.app

# 2. Package it — notarytool only accepts .dmg, signed flat .pkg, or .zip
ditto -c -k --keepParent HelloApp.app HelloApp.zip

# 3. Submit and block until Apple answers (usually minutes)
xcrun notarytool submit HelloApp.zip -p "FocusBear-Notary" --wait

# 4. If it failed, read why — the log is JSON and names the offending binary
xcrun notarytool log <submission-id> -p "FocusBear-Notary" developer_log.json

# 5. Staple the ticket to the .app (not the .zip), then re-zip for distribution
xcrun stapler staple HelloApp.app

# 6. Verify like a user's Mac would
xcrun stapler validate HelloApp.app
spctl -vvv --assess --type exec HelloApp.app
```

Stapling matters because it embeds the ticket in the artifact. Without it the app
still passes *if* the Mac can reach Apple's servers, since the notary service also
publishes tickets online — but an offline first launch fails. Staple the artifact
you actually ship: the `.app` inside a zip, or the `.dmg` / `.pkg` itself.

## What Apple requires before it will pass

Every one of these is a real rejection reason with its own error string:

| Requirement | Error if missing |
| --- | --- |
| Valid code signature, unmodified after signing | `The signature of the binary is invalid.` |
| Developer ID certificate (not Mac Distribution, ad hoc or self-signed) | `The binary is not signed with a valid Developer ID certificate.` |
| Secure timestamp (`--timestamp`, or `OTHER_CODE_SIGN_FLAGS`) | `The signature does not include a secure timestamp.` |
| Hardened runtime (`--options runtime`) | `The executable does not have the hardened runtime enabled.` |
| No `com.apple.security.get-task-allow` entitlement | `The executable requests the com.apple.security.get-task-allow entitlement.` |
| Linked against the macOS 10.9 SDK or later | `The binary uses an SDK older than the 10.9 SDK.` |
| Entitlements as ASCII XML, no BOM, not a binary plist | `Embedded entitlements are invalid: syntax error near line 1` |

The `get-task-allow` one is the classic trap: Xcode injects that entitlement at
build time so you can attach the debugger, and strips it during the standard
export. A hand-rolled export script that skips that step gets rejected.

Useful checks before submitting:

```bash
codesign -vvv --deep --strict HelloApp.app     # signature valid and deep-checked
codesign -dvv HelloApp.app                     # "Timestamp=" means secure timestamp
                                               # ("Signed Time" means there isn't one)
codesign -d --entitlements :- HelloApp.app     # "bplist00" here = malformed entitlements
```

## Where HelloApp stands

The 7.x `HelloApp` isn't notarizable as it sits: it's signed for local running,
not with a Developer ID Application certificate, and hardened runtime isn't
enabled. To ship it I'd need a paid Apple Developer Program membership, then
enable **Hardened Runtime** in Signing & Capabilities, archive, and use
Organizer's Developer ID → Upload flow — which does the codesign → notarytool →
stapler sequence above for me.

## What I learned

The tools split cleanly by responsibility, and the order matters: `codesign`
proves *who* built it, the notary service checks *what's inside it*, and
`stapler` makes that verdict travel with the file. Almost every notarization
failure is really a signing failure caught late — which is why `codesign -dvv`
and `spctl --assess` are worth running locally before spending a round trip on
Apple's servers. The one thing you can't shortcut is the certificate: no
Developer ID, no notarization, regardless of how clean the build is.

## Sources

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Apple
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — Apple
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) — Apple
- [`notarytool(1)` man page](https://keith.github.io/xcode-man-pages/notarytool.1.html)
- [macOS Sequoia Gatekeeper override change](https://www.macrumors.com/2024/08/06/macos-sequoia-gatekeeper-security-change/) — MacRumors
