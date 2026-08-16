# 8.2 Permission Request App

**Deliverable:** Swift sample requesting 2 permissions.

`HelloApp` now has a **Permissions** sheet that requests two TCC-protected
permissions and shows the whole lifecycle for each — current status, the request,
what happens on denial, and proof the grant works.

| Permission | Framework | Status API | Request API |
| --- | --- | --- | --- |
| **Camera** | AVFoundation | `AVCaptureDevice.authorizationStatus(for: .video)` | `await AVCaptureDevice.requestAccess(for: .video)` |
| **Contacts** | Contacts | `CNContactStore.authorizationStatus(for: .contacts)` | `try await CNContactStore().requestAccess(for: .contacts)` |

Code: `XcodeDeepDive/HelloApp/HelloApp/PermissionsView.swift`, reachable from the
**Permissions…** button in the main window.

## Three things have to line up

A permission request fails — often loudly — unless all three are in place:

| Piece | Where it lives | If it's missing |
| --- | --- | --- |
| Purpose string | `INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSContactsUsageDescription` | **The app crashes** when it asks |
| Sandbox entitlement | `HelloApp.entitlements` — `com.apple.security.device.camera`, `com.apple.security.personal-information.addressbook` | Request is refused with no prompt |
| User consent | TCC, at runtime | Denied until the user changes it in System Settings |

The purpose strings are set as build settings because the project uses
`GENERATE_INFOPLIST_FILE = YES` — Xcode synthesises the `Info.plist` at build
time, so there's no file to edit. The entitlements moved into a real
`HelloApp.entitlements` file, wired up with `CODE_SIGN_ENTITLEMENTS`, because
camera and contacts access have no toggle in the generated-entitlements build
settings.

## How the sample is structured

```text
PermissionState        # one vocabulary for both frameworks:
                       # notDetermined / granted / denied / unknown
CameraPermission       # state, request(), describeDevice()
ContactsPermission     # state, request(), contactCount()
PrivacyPane            # deep links into System Settings
PermissionsView        # two rows + refresh
```

Each framework has its own authorization enum, so the first job is mapping both
onto one type the view can render. `.restricted` collapses into "denied" — from
the app's point of view they're the same thing, since neither can be resolved by
asking again.

```swift
enum CameraPermission {
    static var state: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:       return .notDetermined
        case .authorized:          return .granted
        case .denied, .restricted: return .denied
        @unknown default:          return .unknown
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
```

The `@unknown default` isn't ceremony: Contacts gained a `.limited` case on newer
systems, and an app that switches exhaustively over today's cases breaks when
Apple adds tomorrow's.

## Behaviour worth noticing

- **Only `.notDetermined` can prompt.** Once the user answers, calling
  `requestAccess` again returns the stored decision without showing anything. The
  UI reflects this: the *Request access* button is replaced by *Open System
  Settings…* once the answer is "no".
- **Denial is a normal path, not an error.** The sheet keeps working; it just
  can't show the camera name or the contact count.
- **Never cache a grant.** The user can revoke access in System Settings while
  the app is running, so the view re-reads status in `onAppear` and offers a
  manual refresh.
- **Proof of access.** Once granted, the row shows something only possible with
  the permission — the camera's `localizedName`, or the number of contacts the
  app can enumerate. Without that, a green "Granted" label proves nothing.

## Testing it

```bash
# Ask again from scratch
tccutil reset Camera com.krisha.HelloApp
tccutil reset AddressBook com.krisha.HelloApp

# Watch macOS make the decision
log stream --predicate 'subsystem == "com.apple.TCC"' --info
```

Camera and Contacts both live in **System Settings → Privacy & Security**. The
deep links the app uses are
`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera` and
`…?Privacy_Contacts`.

Debug builds get re-signed on every run, and TCC keys decisions to the code
signing identity, so expect to be asked repeatedly during development — that's
the mechanism from 8.1 working as designed, not a bug.

## What I learned

The request API is the easy part; the surrounding contract is where the work is.
A purpose string is not documentation — leave it out and the process is killed at
the moment it asks, which is a much sharper failure than a denial. And because
the sandbox entitlement, the purpose string and the user's answer are three
independent gates, "permission denied" can mean three quite different things, so
the first debugging question is always *which* gate closed.
