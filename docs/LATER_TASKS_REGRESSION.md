# Later tasks automated regression

## 2026-10-06 — Integrated verification (TASK-010)

**Pass:** 268/268 shared-scheme hosted tests, explicit Debug build, and Release build. No failed or skipped tests in the final run. The combined changed-data reopen regression passed. These results establish automated feature evidence; TASK-011 actual-interface acceptance remains pending.

### Source and environment

- Checkout: `/Users/nstn/.codex/worktrees/later-tasks/MenuPeek`, branch `feat/later-tasks`, base revision `c1891ab9d554c318cae0bd9a0ceb3275cacae5f2`.
- Build inputs: that revision plus the new `testIntegratedChangedDataReopenPreservesBothTablesAndScopedPreferences` in `Tests/MenuPocketTests/DailyNotesStateTests.swift`. No production source changed during this task. The evidence/index documents and ignored English plan were updated after builds.
- Sorted tracked app/test/project file SHA-256 manifest digest: `b125e6b62ddbe3983577d16f4f03d20996bf3402220d1c84b8f50c22de6e9ea6`. Full per-file manifest: `build/task010/source-identity.json`; test diff: `build/task010/test-input.diff`.
- Xcode 27.0 (`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS SDK 27.0; local arm64 Mac running macOS 26.6.2 (`25G83`). Shared `MenuPocket` scheme and macOS destination; final tests ran at approximately 14:07 EDT.
- Dedicated `build/task010/DerivedData` avoids another active checkout's test session and preserves existing app outputs. No production app was launched or upgraded.

### Commands and results

From the checkout, the final commands were:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task010/DerivedData \
  -resultBundlePath build/task010/full-tests-final.xcresult test

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task010/DerivedData build

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/task010/DerivedData build
```

| Check | Result | Retained local evidence |
| --- | --- | --- |
| Full hosted suite | Pass, 268 tests, 0 failures, 0 skipped | `full-tests-final.log`, `full-tests-final.xcresult`, `test-summary.json` |
| Explicit Debug build | Pass | `debug-build.log` |
| Release build | Pass, arm64 and x86_64 | `release-build.log` |
| Signature verification | Pass, both bundles, `codesign --verify --deep --strict` | `artifact-identity.json`, `debug-signature.txt`, `release-signature.txt` |
| Production files/main app preservation | Pass, nine baseline file hashes unchanged | `preservation-before.json`, `preservation-final.json` |
| Temporary app cleanup | Pass, all three generated bundles | `cleanup.json`, `failed-build-trash.json`, `final-trash-paths.json` |

Evidence filenames above are under `build/task010/`. Logs/result bundles remain ignored local evidence; this document retains essential outcomes and identity independently.

Suite counts: AppConfiguration 48; DailyNotesState 66; SQLiteNoteRepository 33; TaskCategoryPreferences 8; TaskGrouping 8; LaterTaskDomain 3; QuickAddPanel 8; AppModelLoading 15; AppModel 18; DemoModuleProvider 6; HotKeyService 14; LoginItemService 5; LoginItemSettings 10; ModuleCatalog 3; NoteDomain 9; PreferencesStore 14.

### Behavior and preservation coverage

| Contract | Verified automated evidence |
| --- | --- |
| Migration and schema refusal | Existing v0/v1/v2 fixtures preserve daily data/rowids/categories; migration failure rolls back schema/data/version and retries; valid v3 reopens without byte changes; newer/incompatible schemas are refused without repair. |
| Later CRUD and move | Existing SQLite/state tests cover IDs, insertion order, metadata, completed/missing/colliding sources, insert/delete failure rollback, retry and single transfer. A move uses the action-time local day and publishes only committed results. |
| Shared categories | Counts include daily history and Later, including completed rows. Rename/removal preserve tasks, clear assignments atomically, recover from failure, and reconcile both preference scopes. |
| Availability and day boundaries | Later-only failure preserves Today status, Today-only failure preserves Later; catalog failure invalidates both. Injected midnight/time-zone changes preserve Later interactions and invalidate stale daily actions. |
| Drafts, guards and commands | Scoped editing/deletion/category guards, independent drafts, retained window selection, native Command-N/Return, safe status Today request, Show Tasks retention, fresh/quiet launch and termination regressions pass. |
| Status and Quick Add | Today-only status and Quick Add's Today/General destination remain independent of Later selection, drafts and remembered category. Tests inject fake registration services; no real global shortcut or login registration is requested. |

The new integrated regression uses a unique temporary SQLite database, isolated UserDefaults suite, injected Toronto clock and notification centers. It seeds saved history/Today and Later tasks, edits and completes a Later task, moves another once, renames a remaining category and removes a shared category used by history and Later. It confirms the completed Later row remains, Today progress changes only on move, historical task metadata/rowids remain, and shared removal deletes no tasks. It then stops the first state (closing its repository), opens a fresh state/connection and preference owner **without reseeding**, and compares all columns/rowids in `notes`, `later_tasks`, and `categories`, both saved snapshots, the complete isolated defaults dictionary, the encoded app preferences/onboarding bytes and Today presentation choices. Deleted Later category choices fall back to General.

This is a headless changed-data reopen, not a native quit/relaunch observation. The test stores an enabled Quick Add preference as data only; it creates no AppModel or hotkey/login service.

The Debug host skips the production delegate. Existing hosted lifecycle fixtures use isolated repositories/defaults and fake services for mutations; services constructed with real defaults in read-only model tests do not request registration. The assembled source was inspected against the Later contract: additive schema v3, explicit transaction/rollback boundaries, destination-scoped actions, committed transfer publication, guarded presentation and Today-only native routes. No implementation defect required a production change in this task.

Read-only SHA-256 baselines covered both existing app executables/Info.plist/signature resources, the production sandbox `notes.sqlite`, sandbox preferences plist and external preferences plist. All nine matched after tests/builds and final cleanup. No SQLite sidecar was present in the baseline/final snapshot. These hashes support file preservation; they do not establish a genuine system login or shortcut observation.

### Artifact identity and handoff

Both apps have bundle ID `local.menupocket.app`, version `0.1.0`, build `1`, App Sandbox and the project's existing local ad hoc signing/entitlements. Original paths before cleanup:

- Debug: `/Users/nstn/.codex/worktrees/later-tasks/MenuPeek/build/task010/DerivedData/Build/Products/Debug/MenuPocket.app` (arm64).
- Release: `/Users/nstn/.codex/worktrees/later-tasks/MenuPeek/build/task010/DerivedData/Build/Products/Release/MenuPocket.app` (x86_64 and arm64).

| Artifact | Executable SHA-256 | Bundle manifest SHA-256 |
| --- | --- | --- |
| Debug | `51a2ba6908fd215ecea1290e4cae98dab5e9b5db912ee156252c284bf7e5440b` | `6841d2e08558c7a72c6f55004d1a09609cbcb1f0fc6c6b490edfc2c36f9735da` |
| Release | `26650836fda528d69359bf94fa20f257be01095a299d3d73bd6a30b78cd31ba1` | `c59289abdb4aed348527c35492b6271c01528072acaff8eec7e5c4d651ba95a3` |

Bundle manifest digests hash sorted JSON mapping each relative file path to its SHA-256, including dylibs/resources/signature files; the full manifests are in `artifact-identity.json`. They identify the built contents more fully than the Debug entry executable alone.

Final test log SHA-256: `b730b16ba4f31cfe185e8428f617aba494367d582f069e6cc80791828ee387b4`. Full log/evidence checksums: `build/task010/evidence-sha256.json`.

TASK-011 must identify its own running artifact and isolated dependency identities before observations. These disposable artifacts have been removed, so a rebuild/fixture must record new hashes and tie observations to that artifact and its source inputs. Any subsequent app-source change requires affected verification again. No current running-artifact interface acceptance is claimed.

### Failures, cleanup and remaining gate

- Initial sandbox test build failed in Swift macro/plugin access before XCTest: `full-tests.log`, `full-tests.xcresult`. Required local access resolved that environment restriction.
- First authorized build found a missing `completedAt: nil` argument in the newly added test: `full-tests-authorized.log`, `full-tests-authorized.xcresult`. It was fixed before the final passing suite. Its generated Debug bundle was trashed/unregistered before rerun.
- XCTest host PID 91884 exited. Final Debug and Release bundles were unregistered by exact path and moved via `FileManager.trashItem`; returned Trash paths were then unregistered. A stale Release original-path LaunchServices record was detected and cleared on recheck. Some unregister calls returned `-10814` for already absent registrations; fresh dumps, rather than those exit codes alone, establish the final result.
- Final exact original/Trash path checks passed for processes, Spotlight and LaunchServices; original bundle paths are gone. Baseline apps and saved files remain unchanged. All three bundles, including failed-build output, are tracked in `cleanup.json`. Trash was not emptied; another session's artifacts were preserved.
- **Not tested here:** native layout/appearance/focus journeys and changed-data quit/relaunch, production-identity status click/global hotkey, genuine Dock/login behavior, actual midnight, VoiceOver, CI and real-data upgrade. Prior focused interface observations remain historical evidence in [Desktop regression](DESKTOP_TASK_REGRESSION.md); they do not substitute for TASK-011's assembled-feature acceptance.

TASK-010's automated gate is complete. TASK-011 is ready for isolated native acceptance; full-feature acceptance remains pending.


## 2026-10-06 — Focus regression repair after independent review

The first independent review returned **CHANGES REQUIRED**: its fresh full suite passed 267 tests and failed the existing Later editor transition test. The actual failure was waiting for the reopened inline editor at AppConfigurationTests.swift:940, followed by missing native field-editor assertions. The earlier description of a key-window assertion was inaccurate. Historical report: `build/task010-review/review.md`; this failure remains retained evidence.

A bounded unchanged-source reproduction passed 9/10 Later runs and failed one at the opposite edit-to-Add transition (line 936). Both native fields shared FocusControl.draft. `TaskWindowView` now binds Add to .draft and inline Edit to .edit(taskID), and requests the corresponding focus value. This keeps replacing fields from reusing the same focus identity; existing request cancellation/scroll ownership and behavior assertions remain intact. No test timeout, assertion or production storage behavior was weakened.

Author verification of the revised source:

- Ten Later iterations passed. The paired ten Today iterations passed nine and failed one after the editor text became a single `f` during the stability assertion. Its cause is unproven; it remains in `build/task010-focus-fix/after-focused.log`, not counted as a fully passing stress run.
- Final full shared-scheme suite passed 268/268, no skipped tests: `build/task010-focus-fix/full-final.log`, `full-final.xcresult`, `test-summary.json`.
- Explicit Debug and universal Release builds passed: `build/task010-focus-fix/debug-build.log`, `release-build.log`.
- Scoped actual-interface checks using production views/state in a unique diagnostic fixture observed Later edit cancellation → Add, Add cancellation → inline edit, native Return retaining saved completion and Today draft, and Today edit cancellation → Add. Native entry uses a fixture-only Command-E action, not a production shortcut or accepted row-menu probe. CUA row-menu attempts did not enter edit and are explicitly excluded. Artifact/dependency/action evidence: `build/task010-focus-fix/native/artifact-identity-final.json`, `actions.md`, `snapshot-1.json` through `snapshot-4.json`. Final fixture executable SHA-256: `be0f2b76cb29dfebf58861d2e49d5a9b3c5419e23a8ae40a00765632993b4180`, PID 17916.
- All nine baseline main-app/data/preference hashes matched after sessions. Disposable original paths are gone; generated apps were quit, moved through FileManager Trash and unregistered. Exact-path final checks are recorded in `build/task010-focus-fix/cleanup.json`. An intermediate cleanup verification stopped on re-registration of an earlier Trash path; final re-unregistration cleared it. Directory listing of Trash was denied by macOS privacy; cleanup used returned exact paths, not a directory sweep.

Revised base remains `c1891ab9d554c318cae0bd9a0ceb3275cacae5f2`, plus TaskWindowView.swift focus repair and the previously added DailyNotesStateTests.swift regression. Sorted build-input manifest SHA-256: `27816e8515632c45ac3c1b947e1250fa14a9713a65d6270e46cd70e8dd86af86`; full per-file mapping: `build/task010-focus-fix/source-identity.json`. Original Task 10 artifact hashes above are historical after this production-source change.

| Revised artifact | Executable SHA-256 | Bundle manifest SHA-256 |
| --- | --- | --- |
| Debug | `bb0aca5a17a01730e980295b7eb4e4a3518f898371c450bc03ab5113f6c555a3` | `8a24b8a35f87dc04d6974635d8f47e5758ecc4fb3a49d4cd6173d03e685a9808` |
| Release | `834d43c0fc8c57b467e2a9964f71fc783dca370fca543db4228ee5155ee8911a` | `81c2930f1739ca83c4a00e53e09f4affbc3919ce30b825b71c8e7c25436a9501` |

Both paths used `build/task010-focus-fix/DerivedData/Build/Products/{Debug,Release}/MenuPocket.app` and were removed after identity capture. The same Xcode/toolchain and shared scheme as the original section were used; commands replace DerivedData/result paths with this isolated directory. Bounded reproduction added `-only-testing:MenuPocketTests/AppConfigurationTests/testLaterInlineEditorEscapeAndReturnPreserveTodayDraftAndSavedCompletion -test-iterations 10`; the paired run also selected `testInlineEditNativeReturnFailureAndEscapePreserveSavedTaskAndAddDraft`.

Independent re-review was pending when the author session ended, then stopped at the user's request. The resumed result is recorded below. Full TASK-011 native acceptance and remote CI remain separate gates.


## 2026-10-06 — Resumed independent review: READY

Independent reviewer `/root/task010_independent_review` did not author or design the test or focus repair. Resumed verification returned **READY for TASK-010 automated handoff plus the scoped focus fix**, with no actionable finding remaining.

- Both affected native editing tests passed ten iterations each: **20/20**, zero failures (`build/task010-review-resumed/focus-tests.log`, `focus-tests.xcresult`, `focus-summary.json`).
- Fresh full shared-scheme suite passed **268/268**, zero failures/skipped (`full-tests.log`, `full-tests.xcresult`, `test-summary.json` in the same resumed directory).
- Explicit Debug and universal Release builds, strict signature verification, nine-file main-app/data/preferences preservation and exact-path cleanup passed. Both disposable reviewer bundles were removed; returned Trash paths were unregistered and process/LaunchServices/Spotlight absence verified (`cleanup.json`, `cleanup-verified.txt`).
- The prior author stress failure where the Today editor became `f` did not recur. Its cause remains unproven; the fresh bounded repetitions and full suite establish current stability without claiming a universal guarantee. Earlier failed/stopped reviews are retained as history, not reused as approval.

Reviewed base/HEAD remains `c1891ab9d554c318cae0bd9a0ceb3275cacae5f2`; reviewed build-input manifest remains `27816e8515632c45ac3c1b947e1250fa14a9713a65d6270e46cd70e8dd86af86`. The review's pre-status-update tracked-plus-target/plan manifest was `f63bc34f10b69e45784dec389bc7f25415aafb746bedd696cc352c12941cf331`; documentation/status updates record this result without changing app/test inputs. The requirement-to-proof map, exact commands, stable-snapshot mappings and limitations are in `build/task010-review-resumed/review.md`, `snapshot-before.json` and `snapshot-final.json`.

| Independent artifact, removed after capture | Executable SHA-256 | Bundle manifest SHA-256 |
| --- | --- | --- |
| Debug (arm64) | `74f3e8d7a3c48ff03e5a9c23af50382973486f8c08f42365d3bea9c5b1b51563` | `e6fe1733b19838916049e9020ac1ba677df10a286698991abe20157ebfeedb5d` |
| Release (x86_64 and arm64) | `e7b8853b0dbb183f940d2526618d1d849677b39ddfea28670e81e1351aebde1b` | `444180cd70956dff995a702348b78521b86ce95de1689e80aef98f0f03153c35` |

Same shared scheme, Xcode/toolchain and commands as above, with `build/task010-review-resumed/DerivedData` and the resumed result paths. No commit/push/PR occurred. Readiness is for this Task 10 change set and focus repair; TASK-011 full native acceptance, remote CI, production upgrade and release remain separate gates.
