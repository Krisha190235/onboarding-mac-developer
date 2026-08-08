# 7.5 Build Settings & Schemes — Debug vs Release

A summary of how the `HelloApp` project (`XcodeDeepDive/HelloApp`) is configured,
and how its **Debug** and **Release** build configurations differ. The values
below are the actual settings from `HelloApp.xcodeproj`.

## The three concepts

- **Build settings** — the hundreds of key/value flags that control how the
  compiler and linker build the app (optimization, warnings, code signing,
  deployment target, etc.). Seen under the target's **Build Settings** tab.
- **Build configurations** — named *sets* of build settings. Every Xcode project
  starts with two: **Debug** (fast to build, easy to debug) and **Release**
  (optimized, for shipping). You can inspect them side by side in Build Settings.
- **Schemes** — define *what* gets built and *which configuration* each action
  uses. In `HelloApp`'s scheme: **Run** and **Test** use **Debug**, while
  **Profile**, **Analyze**, and **Archive** use **Release**. You change these in
  *Product → Scheme → Edit Scheme…*.

So the day-to-day rule: pressing ⌘R gives you a Debug build; archiving for
distribution (or ⌘I to Profile) gives you a Release build.

## Debug vs Release — the settings that actually differ

| Build setting | Debug | Release | Why it matters |
|---|---|---|---|
| `SWIFT_OPTIMIZATION_LEVEL` | `-Onone` (no optimization) | `-O` (optimized, default for Release) | Release code runs faster; Debug keeps code straightforward so the debugger maps cleanly to source. |
| `SWIFT_COMPILATION_MODE` | incremental (default) | `wholemodule` | Release compiles the whole module together for better cross-function optimization; Debug compiles per-file for faster incremental builds. |
| `GCC_OPTIMIZATION_LEVEL` (C/Obj-C) | `0` | default (optimized) | Same idea for any C/Obj-C code. |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | `DEBUG` | (unset) | Lets you write `#if DEBUG` code (extra logging, test hooks) that is stripped from Release. |
| `GCC_PREPROCESSOR_DEFINITIONS` | `DEBUG=1` | (unset) | The C/Obj-C equivalent of the `DEBUG` flag. |
| `ENABLE_NS_ASSERTIONS` | on (default) | `NO` | Assertions run in Debug to catch bugs; disabled in Release for speed. |
| `ENABLE_TESTABILITY` | `YES` | (unset → NO) | Debug exposes internals to test targets (`@testable import`); Release keeps them sealed. |
| `ONLY_ACTIVE_ARCH` | `YES` | (unset → NO) | Debug builds only your Mac's architecture (faster); Release builds all supported architectures. |
| `DEBUG_INFORMATION_FORMAT` | `dwarf` | `dwarf-with-dsym` | Release also produces a **dSYM** file so crash reports from the field can be symbolicated. |
| `MTL_ENABLE_DEBUG_INFO` | `INCLUDE_SOURCE` | `NO` | Metal shader debug info included in Debug only. |

**Settings shared by both** (not configuration-specific): deployment target
`macOS 26.5`, `SWIFT_VERSION = 5.0`, bundle id `com.krisha.HelloApp`,
app sandbox enabled, automatic code signing, SwiftUI Previews enabled.

## What this means in practice

- **Debug** = *build fast, debug easily.* No optimization, assertions on, `DEBUG`
  flag set, testability on, single-architecture. You get accurate breakpoints and
  variable inspection (the reason 7.3's LLDB session behaved so cleanly), at the
  cost of slower runtime and a larger, unoptimized binary.
- **Release** = *run fast, ship safely.* Full optimization and whole-module
  compilation, assertions and `DEBUG` code stripped, all architectures built, and
  a dSYM generated for symbolicating real-world crashes. Harder to step through,
  which is why you profile (7.4) and ship with this configuration.

The trade-off is deliberate: you develop against Debug for speed and
inspectability, then validate performance and ship against Release.

## Capture guide (optional screenshots)

1. Select the project in the navigator → **HelloApp target → Build Settings** tab.
   Set the filter to **All** and search `optimization`. You'll see
   *Optimization Level* = *No Optimization [-Onone]* under Debug and
   *Optimize for Speed [-O]* under Release.
   → *Screenshot: the Optimization Level row showing Debug vs Release.*
2. Search `compilation conditions` to show `DEBUG` present only under Debug.
   → *Screenshot: Active Compilation Conditions.*
3. **Product → Scheme → Edit Scheme…** → select **Run** (left) to show
   *Build Configuration: Debug*, then **Archive** to show *Release*.
   → *Screenshot: the scheme editor's build configuration dropdown.*

Save any screenshots into `XcodeDeepDive/screenshots/` and link them below.

## Screenshots

<!-- Optional. Example: ![Optimization](screenshots/05-optimization.png) -->

1. Build Settings — Optimization Level (Debug vs Release)
2. Edit Scheme — build configuration per action
