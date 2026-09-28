# Notes MVP regression — 2026-09-27

This is the TASK-010 automated-check handoff for TASK-011. It records one build and test run, not ongoing verification of later source changes or the running interface.

## Source and environment

- Source revision: `2277c8395522cf29a5284b9b026fc98ecb851dd2`.
- Working tree at verification: only the unrelated, staged-add/working-tree-delete entries for root-level `NOTES_MVP_PLAN.md` and `NOTES_MVP_TASKS.md` were present. Neither file is an Xcode build input. The current local copies live under ignored `plan/mvp/`.
- Host: macOS 26.6.2, arm64; Xcode 27.0 (27A266).
- Built app: `build/DerivedData/Build/Products/Debug/MenuPocket.app`, version 0.1.0 (1).
- Built executable SHA-256: `d5c1f8c14025d5e61c59c3d70f633fdded35c42944a4e8c9c4467120df9660c2`.

## Commands and results

From the repository root, with build products under ignored `build/DerivedData`:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build | Pass | `build/task-010/debug-build.log`: `BUILD SUCCEEDED` at 17:56 local time. |
| Hosted `MenuPocketTests` | Pass | `build/task-010/debug-test.log`: 86 tests, 0 failures; `TEST SUCCEEDED` at 17:56 local time. |

The Xcode result bundle is `build/DerivedData/Logs/Test/Test-MenuPocket-2026.09.27_17-56-33--0400.xcresult`. Logs, result bundle, and build products are ignored local artifacts. The first build attempt in the restricted command sandbox failed when `sandbox-exec` prevented Xcode's Swift macro helper from launching; the same build passed when rerun with the needed process permission. No source or test change was needed.

## Scope of the evidence

The full suite includes note day-boundary, SQLite persistence and failure, daily state, preferences, demo code, Settings window, and login-item fake-service tests. Existing demo tests were retained because the dormant demo implementation remains in the project. README and current docs describe the notes workflow and separate SQLite from `UserDefaults` preferences.

TASK-011 still needs hands-on checks in the running macOS app: both appearances, empty and long lists, add/check/edit/delete, keyboard and focus, relaunch and day changes, storage failure presentation, Settings and Quit. This run did not verify real login startup or a Release artifact. Any source change after this run requires affected checks and acceptance evidence to be repeated.
