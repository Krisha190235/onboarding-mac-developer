# 8.3 Accessibility APIs

**Deliverable:** code snippet interacting with the AX API.

The snippet: [`macOSPermissions/AXProbe.swift`](AXProbe.swift) — a read-only
probe that reports which app is frontmost, the title of its focused window, what
has keyboard focus, and a slice of the window's element tree.

```bash
swift macOSPermissions/AXProbe.swift
```

Grant **Accessibility** to the app that *runs* it — Terminal or iTerm — in
System Settings → Privacy & Security → Accessibility. TCC attributes the request
to the responsible parent process, not to the `swift` binary.

## Why it isn't inside HelloApp

**A sandboxed app cannot use the Accessibility API to inspect other processes.**
This isn't a permission that can be granted around: `AXUIElementCreateApplication`
and friends fail even when the user has ticked the app in Settings. That's why
this is a standalone script rather than another screen in `HelloApp`, which is
sandboxed (see 8.4).

The practical consequence for something like Focus Bear is significant: an app
that needs to see what you're working in **can't ship on the Mac App Store**,
because the store requires the sandbox. Direct distribution with Developer ID is
the only route.

## The model

The AX API is the same interface VoiceOver uses. Every app exposes a tree of
**`AXUIElement`** values — application → windows → groups → buttons, text fields
and so on — and each element has untyped attributes you copy by name.

| Concept | API |
| --- | --- |
| Element for a process | `AXUIElementCreateApplication(pid)` |
| Element for "whatever has focus" | `AXUIElementCreateSystemWide()` |
| Read an attribute | `AXUIElementCopyAttributeValue(element, kAXTitleAttribute, &value)` |
| Write an attribute | `AXUIElementSetAttributeValue(...)` |
| Press a button, raise a window | `AXUIElementPerformAction(element, kAXPressAction)` |
| Watch for changes | `AXObserverCreate` + `AXObserverAddNotification` |

Useful attributes: `kAXWindowsAttribute`, `kAXFocusedWindowAttribute`,
`kAXFocusedUIElementAttribute`, `kAXRoleAttribute`, `kAXTitleAttribute`,
`kAXValueAttribute`, `kAXChildrenAttribute`, `kAXSelectedTextAttribute`.

The core of the probe:

```swift
let front = NSWorkspace.shared.frontmostApplication!
let appElement = AXUIElementCreateApplication(front.processIdentifier)

var value: CFTypeRef?
let error = AXUIElementCopyAttributeValue(appElement,
                                          kAXFocusedWindowAttribute as CFString,
                                          &value)
if error == .success,
   CFGetTypeID(value!) == AXUIElementGetTypeID() {
    let window = value as! AXUIElement
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
    print(title as? String ?? "(untitled)")
}
```

Two things this shows about the API's C heritage:

- **Attributes are untyped.** Every value comes back as `CFTypeRef`, so the code
  has to check `CFGetTypeID` before casting. Assume wrong and it's a crash, not a
  `nil` — which is why the script wraps every read in a small typed helper.
- **Errors are values, not exceptions.** `AXError` distinguishes "you don't have
  permission" (`.apiDisabled`) from "this app doesn't publish that attribute"
  (`.notImplemented` / `.attributeUnsupported`) from "the app is busy"
  (`.cannotComplete`). Collapsing them all into `nil` throws away the only
  diagnostic you have, so the probe prints the error name.

## Permission behaviour

Accessibility is the awkward permission from 8.1:

- `AXIsProcessTrusted()` — check, no side effects.
- `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — shows a
  nudge that offers to open System Settings. It **cannot grant anything**.
- Trust is keyed to the code signature, so a rebuilt debug binary is a new client
  and needs granting again.
- After a grant, apps generally need a relaunch before AX calls start working.

## Reliability notes

Real-world use of this API is less tidy than the sample suggests:

- Not every app implements every attribute — Electron and Java apps are
  notoriously patchy, and browsers expose tabs inconsistently.
- Calls are synchronous IPC into another process. If that app hangs, your call
  blocks, so a foreground poll needs a timeout
  (`AXUIElementSetMessagingTimeout`) and should live off the main thread.
- Polling every second (as the probe does) is fine for a demo; production code
  should use `AXObserver` notifications, or `NSWorkspace`'s
  `didActivateApplicationNotification`, and query only on change.

## What I learned

The AX API is the thing that makes a focus app possible and simultaneously the
thing that constrains how it can be distributed — sandboxed apps are locked out
entirely, so the choice of API decides the business model. The API itself is a
1990s C interface wearing a Swift jacket: untyped attributes, out-parameters,
error codes. Wrapping it in a few small typed helpers (as in `AXProbe.swift`)
turns it into something readable, and that wrapper is the first thing I'd write
in any project that touches it.
