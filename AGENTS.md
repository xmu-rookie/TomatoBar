# Repository Guidelines

## Project Structure & Module Organization

`TomatoBar/` contains the macOS app. `TimerEngine.swift` holds pure timer rules;
`Timer.swift` connects them to UI and macOS services. Session persistence and
analytics use `SessionModels.swift`, `SessionRepository.swift`,
`StatisticsEngine.swift`, and their SwiftUI views. Todoist code follows the
`Todoist*.swift` naming pattern; credentials stay in `CredentialStore.swift`.
Assets live in `Assets.xcassets`, localizations in `{en,ko,zh-Hans}.lproj`, and
tests in `TomatoBarTests/`. Project settings and pinned packages are under
`TomatoBar.xcodeproj/`.

## Product Plan & Delivery Rules

[`docs/TOMATRACE_PLAN.md`](docs/TOMATRACE_PLAN.md) defines scope, architecture,
milestones, and acceptance criteria. Update it in the same commit when behavior
or milestones change, and record verification before marking work complete.
Never put Todoist tokens in code, fixtures, logs, screenshots, settings, or Git;
store them in macOS Keychain and redact network errors.

## Build, Test, and Development Commands

- `open TomatoBar.xcodeproj`: open Xcode; choose `TomatoBar > My Mac`, then
  press `Cmd-R`.
- `xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar -configuration Debug CODE_SIGNING_ALLOWED=NO build`:
  build Debug without a signing identity.
- Replace `Debug` with `Release` to validate the optimized build.
- `xcodebuild test -project TomatoBar.xcodeproj -scheme TomatoBar -destination 'platform=macOS'`:
  run all XCTest and persistence tests.

Commit `Package.resolved` when `LaunchAtLogin` or `KeyboardShortcuts` changes.

## Coding Style & Naming Conventions

Use four spaces, declaration-line braces, `UpperCamelCase` types, and
`lowerCamelCase` members. Retain the established `TB` prefix for app-wide types.
Keep SwiftUI views small; move timer, persistence, and network logic out of view
bodies. No formatter is configured, so match nearby code and remove warnings.

## Testing Guidelines

Build Debug and Release for every change. Run the full suite, then manually
check menu-bar launch, popover, timer transitions, notifications, sounds, and
quit. Name tests after the subject, such as `TimerEngineTests.swift`, and assert
observable behavior.

## Commit & Pull Request Guidelines

Use focused, imperative commits, optionally with prefixes such as `docs:`.
Pull requests must describe behavior, verification, and macOS compatibility;
link issues and include before/after screenshots for UI changes. Never commit
certificates, tokens, or user-specific Xcode settings.
