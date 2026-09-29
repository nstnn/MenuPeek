# Desktop task regression and local artifact evidence — 2026-09-29

Task 8's automated regression, storage preservation, local builds, and artifact checks passed. This tracked record imports that existing evidence for the desktop handoff. No tests were added or run, no app was rebuilt, and no interface checks were performed during the Task 10 documentation update. Actual interface results are separate in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md).

## Source and provenance

- Verification base: `dd25383744360e91b80e52ef0f982a31a1d65301`, branch `main`, with the Task 8 change to `Tests/MenuPocketTests/SQLiteNoteRepositoryTests.swift`.
- Recorded test-file SHA-256: `bedcadfa3bb745607f09fbbe1f4e58259cb971f993e608cba8c210477dd8d591`.
- Recorded diff SHA-256: `a4ec31c52bf69aa93b616e8011a97dbf3fbf71e508a6e4b99c456a4ae0a3eaf4`.
- Original 51-entry source/test/configuration/document manifest SHA-256: `a847604ff563841ccf630f607852442e730dd81d3a89e54aba1a9c38450771cf`.
- Task 8's change was committed as `578a0db` and merged into `52cd8e8f3a11d5e2c60494f1622978c6d8299ffe`. Task 9 recorded that clean source revision and no mismatches against Task 8's identity.
- The Task 10 documentation audit compared the 43 recorded app/test/project/CI files with their stored hashes and found no mismatches. Documentation edits change the original full manifest's documentation entries; they do not change build inputs or the retained app.

Recorded environment: macOS 26.6.2 (`25G83`), arm64; Xcode 27.0 (`27A266a`), Swift 6.4; shared `MenuPocket` scheme and `platform=macOS` destination. The verification identity was recorded at `2026-09-29T15:42:05.951688+00:00`.

## Recorded results

| Claim | Recorded result | Evidence and limit |
| --- | --- | --- |
| Shared-scheme Debug suite | Pass | 114 tests, zero failures; retained log reports `TEST SUCCEEDED`, with the suite finishing at 11:36:23 local time on 2026-09-29. This is the Task 8 run, not a Task 10 rerun. |
| Existing SQLite task preservation | Pass | `testExistingVersionOneTodayAndYesterdayRowsSurviveOpenWriteAndReopen` directly seeds schema-1 today/yesterday rows and compares full task identity/text/day/time/completion before and after write/reopen. |
| Unsupported newer schema protection | Pass | `testNewerSchemaIsRejectedWithoutChangingDatabase` retains the populated schema-2 database's exact bytes after rejection. |
| Saved progress and availability | Pass | Empty versus failed reads, failed writes, retry, and successive status observations without a task window are covered. |
| Daily refresh and no carryover | Pass for automated scope | Calendar, wake, clock, time-zone, stale-action, and recovery checks use deterministic fixtures/notifications. They do not establish a genuine system day transition. |
| Draft/error recovery | Pass | Failed add, completion, edit and delete retain saved rows/count and recoverable text; real SQLite trigger-rejection fixtures support state tests. |
| Window, startup and native commands | Pass for hosted scope | All 17 `AppConfigurationTests` cover shared owners, reopen, injected manual/login context, onboarding/preferences isolation, native field/menu commands and termination callbacks. Actual system interaction is separate. |
| Local Release build | Pass | Retained log reports `BUILD SUCCEEDED`. |
| Standalone Debug build | Pass | Built separately from XCTest to inspect normal app entitlements. |
| Metadata, signature and sandbox | Pass | Tested Debug, standalone Debug and Release identities/entitlements were recorded; strict signature checks passed. |
| Independent Task 8 review | Pass within Task 8 scope | Fresh reviewer returned `READY`, independently ran 114 tests and a Release build, and reviewed final artifact/evidence identity. This is historical review, not a new Task 10 review or distribution approval. |
| Remote CI | Not tested in Task 8 | These local results do not establish a GitHub Actions run. |

## Commands retained from Task 8

These commands were executed for the dated Task 8 evidence. They were not executed for this documentation update; ongoing procedures live in [Workflow](WORKFLOW.md).

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/desktop-task-management/task-008/Debug-tests.xcresult test

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/desktop-task-management/task-008/DebugStandaloneDerivedData build
```

## Artifact identity

Task 9 used the retained Release copy at `build/desktop-task-management/task-008/Release/MenuPocket.app`, copied from `build/DerivedData/Build/Products/Release/MenuPocket.app`. Task 8 recorded equal hashes for every file in the built and retained copies; Task 9 checked the same retained bundle.

- Bundle identifier: `local.menupocket.app`; version `0.1.0`, build `1`; English development region; `APPL`; `LSUIElement = false`; minimum macOS `14.0`.
- Release architectures: x86_64 and arm64; ad hoc signature, strict deep signature verification passed.
- Executable SHA-256: `b88c9444017b160ff61e8e82efefa27dc56a6b34ae142ab82a75f7246a95fd98`.
- Bundle manifest SHA-256: `f656e2bdd684bc49c18556e9f154e53a58a483c0b6b507517cafc64a1b840401`, calculated from canonical sorted JSON of bundle-relative file hashes.
- Release executable timestamp: `2026-09-29T15:37:48.128371+00:00`.
- Standalone Debug/Release entitlements: `com.apple.security.app-sandbox = true` and existing `com.apple.security.get-task-allow = true`. The XCTest host additionally had temporary test-host exceptions, recorded separately. This is a local development artifact, not a notarized/public distribution build.

SQLite schema version 1, sandbox storage location, preference/onboarding keys, and login-registration boundary remained unchanged. Automated fixtures used temporary databases, isolated defaults and fake login services. No product app was launched or installed during Task 8.

## Local supporting records and validity

The detailed Task 8 record is `plan/desktop-task-management/evidence/task-008.md`. Raw identity, logs, result bundles, metadata/signature outputs, source patch, retained app, and independent review are under `build/desktop-task-management/task-008/`. Both directories remain Git-ignored; the essential results and identity above are retained in this tracked document for other checkouts.

Build-input or artifact changes require affected automated checks, a rebuilt/identified artifact, and renewed affected interface evidence. Documentation-only changes do not constitute a new build or verification run. Preserve historical [Notes MVP regression](NOTES_MVP_REGRESSION.md) and [acceptance](NOTES_MVP_ACCEPTANCE.md) as earlier compact-panel evidence.

## Focus outline follow-up — 2026-09-29

This is a separate local check for the Today-window focus change, not a replacement for Task 8's results above. Source was `main` at `299edef1af01f12edd6a5f446f372f80aadadce8` with uncommitted focus and documentation changes. Xcode 27.0 (`27A266a`) ran the shared `MenuPocket` Debug scheme with `platform=macOS` and `build/DerivedData`: the final `xcodebuild ... test` run passed 114 tests with zero failures at 14:35 EDT. The resulting Debug executable at `build/DerivedData/Build/Products/Debug/MenuPocket.app/Contents/MacOS/MenuPocket` had SHA-256 `20b4f983e31323d21f9194d0fc6cf63eba1d62c3cfa79b6855f3f8afef240596`. The first sandboxed build could not run Xcode's Swift macro service; the subsequent unsandboxed builds and final test run succeeded. No Release build or remote CI check was run for this follow-up. The matching running-app observation is in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md).

## Fixed task positions — 2026-09-29

Pass for the focused Debug regression: source was `main` at `0c2833ec3d08426bfbc3b1dffb1cd41155c973eb` with uncommitted ordering, preview, test, and documentation changes. The app/test diff SHA-256 was `567cb3a7eacb98f24e661fba5939d5e300557d76a635d06b604027ffd1778ca4`. Xcode 27.0 (`27A266a`) passed all 113 tests with zero failures at 16:57 EDT using:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData SDK_STAT_CACHE_ENABLE=NO test
```

The expanded SQLite-backed state regression exercises equal creation timestamps, a backward same-day clock adjustment, completion/uncompletion, editing, refresh, fresh state instances, middle-row deletion, and subsequent addition. Every surviving task retains its relative insertion order. Existing schema-1 data preservation and unsupported-newer-schema rejection tests also passed. The obsolete domain-sorter test was removed with the sorter; ordering is now exercised through repository-backed behavior.

The initial sandboxed run failed to launch Swift macro services. The first authorized run exposed one remaining expectation for the former ordering; after updating it, the full suite passed. A normal shared-scheme Debug build then passed, with executable SHA-256 `d74b27d5d6d5d8197eb61b346be8b71798bb1cb5925ac071b86fe653e5164b63`. Logs remain under ignored `build/task-order-tests-final.log` and `build/task-order-build.log`. No schema migration, Release build, or remote CI run was performed. Matching interface observations are in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md).
