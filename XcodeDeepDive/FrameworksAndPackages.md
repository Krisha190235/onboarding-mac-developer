# 7.7 Frameworks & Packages

**Deliverable:** add one Swift Package to a project.

`HelloApp` now depends on a Swift package called **CounterKit**, a *local*
package that lives inside the project folder at
`XcodeDeepDive/HelloApp/CounterKit`. The `Counter` and `Workload` types that
used to sit inside `ContentView.swift` now live in the package, and both the app
and the test bundle link against it.

## What a Swift Package actually is

A package is a folder with a `Package.swift` manifest describing its products
(what other code can import), its targets (the modules it builds), and its
dependencies. Swift Package Manager builds it as a separate module, so anything
you want visible outside the package has to be explicitly marked `public` —
which is the main practical difference from just having files in your app target.

| | Framework (`.framework`) | Swift Package |
|---|---|---|
| Described by | Xcode target settings | `Package.swift` manifest, in source control |
| Dependencies | added manually | resolved by SPM, pinned in `Package.resolved` |
| Shared between projects | copy the binary, or a workspace | point at a folder or a git URL |
| Today's default | legacy / binary distribution | what Apple recommends for new code |

## Local vs remote packages

- **Remote:** *File → Add Package Dependencies…*, paste a git URL such as
  `https://github.com/apple/swift-collections`, choose a version rule. Xcode
  resolves it and writes the exact commit into `Package.resolved`, so everyone
  who clones the repo builds against the same version.
- **Local:** the package folder is inside your repo and referenced by relative
  path. No version rule and no resolution step — you edit the package and the
  app picks the change up on the next build.

I used a local package here because the goal was to learn how a package is
*structured* and wired into a target. A remote dependency would exercise version
pinning instead, but wouldn't teach me anything about `Package.swift`.

## The package

```
CounterKit/
├── Package.swift                       # manifest: product + 2 targets
├── Sources/CounterKit/
│   ├── Counter.swift                   # public struct Counter
│   └── Workload.swift                  # public enum Workload
└── Tests/CounterKitTests/
    └── CounterKitTests.swift           # 4 package-level tests
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "CounterKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CounterKit", targets: ["CounterKit"])],
    targets: [
        .target(name: "CounterKit"),
        .testTarget(name: "CounterKitTests", dependencies: ["CounterKit"])
    ]
)
```

The `platforms:` line is the package's *minimum* macOS version. It has to be at
or below the app's deployment target, otherwise the app won't link it.

## How it's wired into HelloApp.xcodeproj

- The project has an `XCLocalSwiftPackageReference` with `relativePath = CounterKit`,
  which is why the package shows up in the navigator with a package icon.
- Both `HelloApp` and `HelloAppTests` have `CounterKit` in
  `packageProductDependencies` and link it in their **Frameworks** build phase.
  The test bundle needs its own link so `import CounterKit` resolves there too.
- Doing it by hand is the same thing Xcode writes when you use
  *File → Add Package Dependencies… → Add Local…*.

## What changed in the app

- `ContentView.swift` lost its `Counter` and `Workload` definitions and gained
  `import CounterKit` — the View is now just a View.
- Everything in the package that the app touches had to become `public`
  (`Counter`, its `init`, `count`, `history`, `doubled`, `increment()`,
  `reset()`, and `Workload.sqrtSum(upTo:)`). Default access is `internal`, which
  stops at the module boundary — the first thing that breaks when you move code
  into a package.
- `HelloAppTests` now does `import CounterKit` instead of
  `@testable import HelloApp`, since the logic it tests is public package API.
  The six tests from 7.6 are unchanged and still pass with ⌘U.

## Tests

The package has its own test target, so the logic is covered from two directions:

| Where | Tests | How to run |
|---|---|---|
| `CounterKitTests` | 4 — empty counter, history length, reuse after reset, `sqrtSum` bounds | `swift test` in the CounterKit folder, or the Test Navigator |
| `HelloAppTests` | 6 (from 7.6) — the app's use of the package | ⌘U in Xcode |

## What I learned

Moving working code into a package is mostly an exercise in access control: the
compiler immediately tells you exactly which parts of your code are actually
API and which were just internal details you'd been reaching into. It also made
the app target smaller and the logic reusable — `CounterKit` has no SwiftUI
import at all, so it would build on iOS or in a command-line tool unchanged.
