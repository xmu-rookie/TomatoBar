# Repository Guidelines

## Project Structure & Module Organization

`TomatoBar/` contains the macOS application source. `App.swift` creates the menu-bar item and popover, `View.swift` defines the SwiftUI interface, and `Timer.swift` owns timer and state-machine behavior. Supporting concerns are separated into `Player.swift`, `Notifications.swift`, `State.swift`, and `Log.swift`.

Application images and sounds live in `TomatoBar/Assets.xcassets`. Localized strings are grouped by locale in `TomatoBar/{en,ko,zh-Hans}.lproj`. `Icons/` contains source artwork and conversion tooling. Xcode project settings and pinned Swift Package dependencies are under `TomatoBar.xcodeproj/`.

Unit tests live in `TomatoBarTests/` and run through the shared `TomatoBar` scheme. Keep test support code in that directory rather than mixing it into the app target.

## Product Plan & Delivery Rules

[`docs/TOMATRACE_PLAN.md`](docs/TOMATRACE_PLAN.md) is the source of truth for the TomaTrace product scope, architecture, milestone order, and acceptance criteria. Before changing application code, identify the current milestone and implement only its smallest independently verifiable step.

Do not skip a milestone's build, automated-test, or manual-verification requirements. Mark a milestone complete only after recording its verification result in the plan. If a requirement, architecture decision, data model, or milestone boundary intentionally changes, update the plan in the same commit so implementation and documentation cannot drift.

Never place Todoist credentials in source code, fixtures, logs, screenshots, build settings, or Git history. Store a user's Token in macOS Keychain and redact it from errors.

## Build, Test, and Development Commands

- `open TomatoBar.xcodeproj` opens the project in Xcode. Select the `TomatoBar` scheme and `My Mac`, then press `Cmd-R`.
- `xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar -configuration Debug CODE_SIGNING_ALLOWED=NO build` performs a local command-line build without requiring a signing identity.
- `xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar -configuration Release CODE_SIGNING_ALLOWED=NO build` checks the optimized configuration used by CI.
- `xcodebuild test -project TomatoBar.xcodeproj -scheme TomatoBar -destination 'platform=macOS'` should be used once a test target is added.

Swift Package Manager resolves `LaunchAtLogin`, `KeyboardShortcuts`, and `SwiftState`; keep `Package.resolved` committed when dependency versions change.

## Coding Style & Naming Conventions

Use four-space indentation, opening braces on the declaration line, and trailing commas in multiline collections where already used. Follow standard Swift naming: types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and enum cases in `lowerCamelCase`. Existing application types use the `TB` prefix, such as `TBTimer` and `TBStatusItem`; retain this convention for app-wide types.

Keep SwiftUI views small and move timer, persistence, notification, or network behavior out of view bodies. The repository has no configured formatter or linter, so match nearby code and remove compiler warnings.

## Testing Guidelines

For every change, build both Debug and Release. Manually verify menu-bar launch, popover opening, start/stop behavior, interval transitions, notifications, sounds, and quitting. Name XCTest files after the subject, for example `TBTimerTests.swift`, and test observable behavior rather than private implementation details.

## Commit & Pull Request Guidelines

Use short, imperative commit subjects, matching history such as `Fix code signing for CI` or `Update KeyboardShortcuts to 2.4.0`. Optional scoped prefixes such as `docs:` are acceptable. Keep each commit focused.

Pull requests should explain the behavior change, verification performed, and any macOS compatibility impact. Link relevant issues and include before/after screenshots for popover or menu-bar UI changes. Never commit signing certificates, API tokens, or user-specific Xcode settings.
