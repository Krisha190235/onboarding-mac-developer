#!/usr/bin/env swift
//
//  AXProbe.swift — 8.3 Accessibility APIs
//
//  A small, read-only probe of the macOS Accessibility (AX) API: it reports
//  which app is frontmost, the title of its focused window, and what the
//  focused UI element is — the same primitives a focus/time-tracking app uses.
//
//  Run it:
//      swift macOSPermissions/AXProbe.swift
//
//  Grant Accessibility to the app that *runs* it (Terminal or iTerm), not to
//  Swift: System Settings > Privacy & Security > Accessibility. TCC attributes
//  the request to the responsible parent process.
//
//  Why this isn't inside HelloApp: a sandboxed app can't query other processes
//  through the AX API at all — the calls fail even if the user grants
//  Accessibility. See macOSPermissions/AccessibilityAPIs.md.
//

import Foundation
import AppKit
import ApplicationServices

// MARK: - Trust check

/// Accessibility is one of the permissions that can never be granted by a
/// prompt. The most an app can do is show the "open Settings" nudge.
func ensureTrusted() {
    if AXIsProcessTrusted() { return }

    print("Not trusted for Accessibility yet.")
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)   // shows the nudge, grants nothing

    print("""

    Add the app running this script (Terminal / iTerm) under
    System Settings > Privacy & Security > Accessibility, then run it again.
    Quitting and reopening the terminal after granting is usually needed.
    """)
    exit(1)
}

// MARK: - Thin Swift wrappers over the C API

/// Copies one attribute, returning nil rather than throwing an AXError around.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else { return nil }
    return value
}

/// Attribute as a String, when the value is textual.
func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

/// Attribute as another element. The type check matters: attributes are
/// untyped CFTypeRefs, so a wrong assumption is a crash rather than a nil.
func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name),
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// Attribute as an array of elements (e.g. a window's children).
func elementsAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    guard let value = attribute(element, name),
          CFGetTypeID(value) == CFArrayGetTypeID(),
          let array = value as? [AnyObject] else { return [] }
    return array.compactMap { item in
        guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
        return (item as! AXUIElement)
    }
}

/// Readable names for the errors worth recognising.
func describe(_ error: AXError) -> String {
    switch error {
    case .success:                return "success"
    case .apiDisabled:            return "apiDisabled (Accessibility not granted)"
    case .notImplemented:         return "notImplemented (app doesn't expose this)"
    case .cannotComplete:         return "cannotComplete (app busy, or not responding)"
    case .invalidUIElement:       return "invalidUIElement (element went away)"
    case .attributeUnsupported:   return "attributeUnsupported"
    case .noValue:                return "noValue"
    default:                      return "AXError \(error.rawValue)"
    }
}

// MARK: - The interesting bit

struct Snapshot: Equatable {
    var app: String
    var window: String
    var focusedRole: String
    var windowCount: Int

    var line: String {
        "\(app) | window: \(window) | focus: \(focusedRole) | \(windowCount) window(s)"
    }
}

func snapshot() -> Snapshot {
    guard let front = NSWorkspace.shared.frontmostApplication else {
        return Snapshot(app: "unknown", window: "-", focusedRole: "-", windowCount: 0)
    }

    let appName = front.localizedName ?? "pid \(front.processIdentifier)"

    // One AXUIElement per process. This is the call a sandboxed app can't make.
    let appElement = AXUIElementCreateApplication(front.processIdentifier)

    let windows = elementsAttribute(appElement, kAXWindowsAttribute as String)

    let windowTitle = elementAttribute(appElement, kAXFocusedWindowAttribute as String)
        .flatMap { stringAttribute($0, kAXTitleAttribute as String) } ?? "(no focused window)"

    // The system-wide element answers "what has keyboard focus right now",
    // regardless of which app owns it.
    let systemWide = AXUIElementCreateSystemWide()
    let focusedRole = elementAttribute(systemWide, kAXFocusedUIElementAttribute as String)
        .flatMap { stringAttribute($0, kAXRoleAttribute as String) } ?? "(none)"

    return Snapshot(app: appName,
                    window: windowTitle,
                    focusedRole: focusedRole,
                    windowCount: windows.count)
}

/// Walks a couple of levels of the element tree, to show that AX exposes a
/// hierarchy rather than isolated values.
func printTree(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 2, limit: Int = 5) {
    let role = stringAttribute(element, kAXRoleAttribute as String) ?? "?"
    let title = stringAttribute(element, kAXTitleAttribute as String)
        ?? stringAttribute(element, kAXValueAttribute as String)
        ?? ""
    let indent = String(repeating: "  ", count: depth)
    print("\(indent)- \(role)\(title.isEmpty ? "" : ": \(title.prefix(60))")")

    guard depth < maxDepth else { return }
    for child in elementsAttribute(element, kAXChildrenAttribute as String).prefix(limit) {
        printTree(child, depth: depth + 1, maxDepth: maxDepth, limit: limit)
    }
}

// MARK: - Main

ensureTrusted()
print("Trusted for Accessibility.\n")

// A demonstration of reading a specific error rather than just nil.
if let front = NSWorkspace.shared.frontmostApplication {
    let appElement = AXUIElementCreateApplication(front.processIdentifier)
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(appElement,
                                              kAXFocusedWindowAttribute as CFString,
                                              &value)
    print("Reading focused window of \(front.localizedName ?? "?"): \(describe(error))\n")
}

print("Sampling for 10 seconds — switch between apps to see it change.")
print("(This poll is exactly what an app-usage tracker does.)\n")

var previous: Snapshot?
for _ in 0..<10 {
    let current = snapshot()
    if current != previous {
        let time = DateFormatter.localizedString(from: Date(),
                                                 dateStyle: .none,
                                                 timeStyle: .medium)
        print("[\(time)] \(current.line)")
        previous = current
    }
    Thread.sleep(forTimeInterval: 1)
}

// Finally, a peek at the frontmost window's element tree.
if let front = NSWorkspace.shared.frontmostApplication,
   let window = elementAttribute(AXUIElementCreateApplication(front.processIdentifier),
                                 kAXFocusedWindowAttribute as String) {
    print("\nElement tree of the focused window:")
    printTree(window)
}

// Writing is possible too — AXUIElementSetAttributeValue to change a value,
// AXUIElementPerformAction(element, kAXPressAction as CFString) to click a
// button. Left commented out: this probe stays read-only on purpose.
