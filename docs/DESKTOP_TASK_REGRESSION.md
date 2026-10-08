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

## Category domain — Task 1, 2026-09-30

Pass for Task 1's domain preparation. Source was `main` at `00781aa709124ddb5030b380d31deb624d7464ed` with uncommitted category model, Note initializer, state/preview copy preservation, Xcode membership, and focused test changes. The eight-file app/test/project manifest, including the new TaskCategory.swift, has SHA-256 `c5c735a9bc2118e978fe9b11509d9625e6a12b9f8abf149f137ab5cdb96b949b`; it is retained under ignored `build/task-categories/task-001/source-manifest.sha256`.

Xcode 27.0 (`27A266a`) compiled the Debug app and hosted test bundle using the shared MenuPocket scheme, `platform=macOS`, and `build/DerivedData`. At 13:04 EDT, the selected NoteDomainTests (9), DailyNotesStateTests (23), and SQLiteNoteRepositoryTests (9) passed: **41 tests, zero failures**. The invocation used `-only-testing:MenuPocketTests/NoteDomainTests`, `-only-testing:MenuPocketTests/DailyNotesStateTests`, and `-only-testing:MenuPocketTests/SQLiteNoteRepositoryTests`. Results are retained at `build/task-categories/task-001/Verified-tests.xcresult`, with log `build/task-categories-task-001-verified-tests.log`. The initial sandboxed attempt failed before testing because Swift Observation macro services could not start; the authorized execution outside the sandbox passed.

Coverage establishes legacy nil-category construction, General-name reservation, trimmed display spelling, canonical/case-folded comparison with significant accents, multiline/blank rejection, stable category identity/order, and association preservation across completion, uncompletion, editing, rejected writes, refresh, and fresh state instances using an in-memory fake. Existing SQLite preservation and newer-schema protection checks passed on isolated databases. General is a nil association, not a seeded category row.

Category persistence, schema migration, category commands, and interface controls remain unimplemented. This result does not establish category persistence across an actual process restart or real-interface acceptance. No full-suite run, Release build, remote CI, or actual-interface check was performed for Task 1. Historical results above remain separate.

## Category schema migration — Task 2, 2026-09-30

Pass for Task 2's isolated storage preparation. Work is uncommitted on `feat/task-categories` at `4a0a5fc80d0c857723754c00f4ba1f7f32ad219c`; the existing category branch was fast-forwarded to current `main` before implementation, preserving the intervening Quick Add changes. The only changed app/test inputs are `SQLiteNoteRepository.swift` and `SQLiteNoteRepositoryTests.swift`. Their manifest SHA-256 is `84438de90b6ba0e510ae72d55da12621c1572ce34187f5c29311b34dedaf4afd`; their diff SHA-256 is `200f305bffe7de8a2d9ba5760d9366456deca9bc3d6d544d844c57f41e44f67a`. Both are retained under ignored `build/task-categories/task-002/` with `identity.json`.

Xcode 27.0 (`27A266a`) built the Debug app and hosted tests on arm64 macOS 26.6.2 (`25G83`). The tests themselves reported **system SQLite 3.51.0**. The final shared-scheme run finished at **17:58:25 EDT** and passed **51 tests, zero failures, zero skipped**: SQLiteNoteRepositoryTests (15), NoteDomainTests (9), and DailyNotesStateTests (27). The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-002/DerivedData \
  -resultBundlePath build/task-categories/task-002/Verified-tests.xcresult \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests test
```

| Claim | Outcome and retained comparison |
| --- | --- |
| Fresh v2 bootstrap | Pass: empty category catalog, optional association, unique name keys and integer creation order, foreign-key rejection, and `ON DELETE SET NULL` preserving fixture tasks across days. These schema checks use direct fixture SQL; category repository commands remain unimplemented. |
| Known unversioned/v1 upgrade | Pass: independently seeded today/yesterday rows with noncontiguous rowids `7, 21, 35, 80` retain `rowid`, UUID, text (including quote/emoji), day key, creation/completion timestamps, relative order, and unfinished counts. Every original association is null. The v1 fixture also adds a task after migration and reopens successfully. |
| Migration rollback/retry | Pass for v0 and v1: an extra legacy index named `notes_category_id_idx` makes creation of the new index fail after the category table and association have been added. Exact `sqlite_master` and original task-row snapshots plus `user_version` equal their pre-upgrade values after rollback. Dropping only the fixture fault permits migration and reopen with preserved rows/counts. No production test hook or validation bypass was added. |
| Connection-level foreign keys | Pass: a trigger attempts an invalid assignment during the repository's text write on each of two opened connections. Both writes are rejected, preserving saved text and null assignment. |
| v2 idempotent reopen | Pass: repeated opens preserve schema snapshot, all saved task values, and database bytes. |
| Incompatible/future protection | Pass: malformed/unknown v0/v1 tables, extra columns, missing primary key, WITHOUT ROWID, wrong day index, unknown SQLite-like table names, incomplete v2, and future version 3 produce storage errors without changing fixture bytes/version. |
| Existing task behavior | Pass: existing CRUD/error/reopen checks and SQLite-backed state ordering, availability, draft/failure, and day-refresh regressions remain passing. |

Results/logs are `Verified-tests.xcresult`, `verified-tests.log`, and `test-summary.json` under that task directory. The first focused run also passed; diff review then tightened the internal-table name filter and added its unknown-table preservation fixture before the final rerun. Review covered schema guards, additive DDL, transaction rollback, rowid preservation, and connection-level enforcement; `git diff --check` passed.

The final Debug bundle is `build/task-categories/task-002/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Its executable SHA-256 is `ef8d8cfe2fcbc7d0ada90d6a1e795f5fb82efc2e9ed49d658c0e17652612c7a6`; `MenuPocket.debug.dylib` SHA-256 is `fb90ce6bb4ad03d1f70b27e6cdd06573e38d2d3d8aeab2e4f7b259377c3250dc`.

Fixtures use per-test temporary databases and are removed by teardown; the Debug XCTest host skips production delegate/storage initialization. No user database was upgraded, no real login/hotkey registration was changed, and no production backup/app launch was performed. Category repository operations, associated-task reads/writes, and interface controls remain later work. No full-suite run, Release build, remote CI, actual-interface acceptance, commit, or push was performed for this card. Before a first real-data launch, follow [upgrade preparation](WORKFLOW.md#schema-v2-upgrade-preparation); a v1 binary cannot reopen v2.

## Category repository operations — Task 3, 2026-09-30

Pass for Task 3's focused automated verification. The changes are uncommitted on `feat/task-categories`, based on `847cea88f1af36adeb0e59edd3572726f0ddab33`. Six Swift inputs changed: the repository protocol/implementation, the daily state's text-edit caller, and the SQLite/state/configuration tests. The SHA-256 of the sorted source-input hash manifest is `fbf87db327513f69353942435323b69d8d98201db0095cee32352aa19389b792`; per-file hashes and identity are retained under ignored `build/task-categories/task-003/` in `source-inputs.json` and `identity.json`.

Xcode 27.0 (`27A266a`) built the Debug app and hosted suite on arm64 macOS 26.6.2 (`25G83`). The result bundle reports **88 passed, zero failed, zero skipped**: SQLiteNoteRepositoryTests (23), DailyNotesStateTests (28), AppConfigurationTests (28), and NoteDomainTests (9). The final command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-003/DerivedData \
  -resultBundlePath build/task-categories/task-003/Verified-tests.xcresult \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/NoteDomainTests test
```

| Claim | Outcome and retained comparison |
| --- | --- |
| Category catalog and naming | Pass through repository APIs: create/rename/reopen preserve UUID/order; names are trimmed and canonically case-folded; duplicate, blank, multiline, reserved, missing-target, and order-overflow errors preserve records. Removing a category does not renumber survivors. |
| Task association and atomic edit | Pass: categorized and General adds/readbacks, text+category edits, category-only reassignment, explicit null selection, completion/uncompletion, and reopen preserve task identity, rowid/order, assigned day, and creation/completion fields as applicable. |
| Failed writes and retry | Pass: fixture AFTER INSERT/UPDATE triggers raise FAIL after category/task changes have begun. Transactions restore the original category catalog and complete task-row snapshots; retry persists successfully without consuming category order on failed creation. |
| All-days usage and removal | Pass: usage includes completed/unfinished tasks from today, yesterday, and an older day. An AFTER association-update failure on an older row rolls back removal and every assignment. Retry clears only the removed ID, retaining all task fields/rowids, other associations, progress, and unfinished counts across reopen. |
| Invalid reads | Pass: malformed category UUIDs, reserved/untrimmed names, mismatched name keys, malformed task references, and orphan references throw without silently falling back to General or repairing the fixture. |
| Caller/fake integration | Pass: both protocol conformers build; the daily state passes the saved category during a text edit. A SQLite-backed state regression preserves association through completion, editing, refresh, connection release/reopen, and uncompletion; existing draft/failure, ordering, availability, lifecycle, and Quick Add configuration regressions pass. |

Results are retained as `Verified-tests.xcresult`, `verified-tests.log`, and `test-summary.json`. The initial restricted-sandbox attempt could not run Xcode compiler plugins; the successful run allowed the required Xcode services. Existing weak-variable compiler warnings and one internal hosted-test QoS warning are retained in the logs/result bundle. Independent acceptance review returned READY for TASK-003.

Independent reviewer `/root/task3_review` did not author or modify the reviewed implementation. The reviewed diff SHA-256 was `7b53c3896daa8953d9d55f6b820ef1c247ed3270893c8ac0fcbd8c36d5e93c57`, with the same six Swift source hashes above. Fresh SQLite (23), state (28), and domain (9) tests passed. An isolated probe held a reader through each of seven mutations, verified a `SQLITE_BUSY` COMMIT failure restored the full raw category/task snapshot, and verified successful retry; writer contention and reopen passed too. Report and probe inputs/logs are retained in `independent-review.md` and `review/` under the Task 3 directory.

Native-test reliability remains a separate limitation: the reviewer combined run passed 87/88 tests, failing one select/copy/cut test (three assertions); a same-environment base run passed 78/79 with a different Settings-close failure (two assertions). Both native tests passed in matched isolated runs on base and patch, 2/2 each. The author's 88/88 run above remains a distinct observation. No identical baseline failure, established environmental cause, or blanket green reviewer suite is claimed. No material Task 3 repository defect was found. Final completion/evidence metadata does not change the reviewed Swift inputs.

The Debug bundle is `build/task-categories/task-003/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `ee02751deb81f443a702e0cad46203dda88f789c240f3bf8431c543c7a9307d3`; debug dylib SHA-256: `6dfcb3a19d76e7218f2aaea4358130711f9bcad518f5f1462cf33a01e9520b02`.

Only temporary databases/defaults and fake system services are used. No production database/app launch, login/hotkey registration, full-suite/Release run, remote CI, commit, or push is claimed. Shared category catalog/commands and drafts, grouped presentation, manager/selector, and actual category interface acceptance remain later cards. The dated Task 1/2 and desktop evidence above retains its original scope.

## Category shared state — Task 4, 2026-10-01

Pass for Task 4's state-only handoff. The clean `main` baseline was `683f62d9e8c90750817978b6172e0f2d3b24b0d0`, containing the committed Task 3 operations. The existing `feat/task-categories` branch was fast-forwarded to that baseline before implementation. Work is uncommitted; the only changed Swift inputs are `DailyNotesState.swift` (SHA-256 `ec9e36cef8d4a74b8bdfd32f3a496f3a71d5588b17643e9be8bf1ba155aaa0d3`) and `DailyNotesStateTests.swift` (`e7929d318ba276db8700a52eb39f7950855d9727f13667c8ed0eb4cb7e47a7d5`). Architecture/requirements now describe the shared catalog; this section retains the dated evidence. Source hashes, identity, and raw review inputs are under ignored `build/task-categories/task-004/`.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app and hosted tests with the shared MenuPocket scheme. Final author verification at 00:05 EDT passed **65/65 tests, zero failures or skipped**: DailyNotesStateTests (37) and AppConfigurationTests (28). The exact command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-004/DerivedData \
  -resultBundlePath build/task-categories/task-004/Final-state-tests.xcresult \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/AppConfigurationTests test
```

Retained results: `Final-state-tests.xcresult`, `final-state-tests.log`, and `final-state-summary.json`. An earlier 97/97 run also covered SQLite/domain tests, but preceded the final rollover-error and assertion changes; its `Verified-tests.xcresult` is intermediate evidence, not final-source verification. Xcode test/report commands needed service/cache access beyond the filesystem sandbox. Existing weak-variable, metadata-extraction, hosted scene/connection, and QoS messages remain in the logs; no compiler or test failure occurred in the final author run.

| Claim | Outcome and proof |
| --- | --- |
| Coherent saved snapshot | Pass: isolated fake failures at catalog, task, or yesterday-count reads preserve the whole same-day saved snapshot and make progress/catalog unavailable. Initial read failures publish nothing; Retry publishes all changed values together. A fake that bypasses referential checking proves the state itself rejects an unknown category ID without relabeling it General. Unused categories remain in saved creation order. |
| Committed category commands | Pass: create/rename return committed values; callbacks verify state has not changed before storage succeeds. Forced follow-up read failures cannot turn committed mutations into failure because commands do not reread. Failed create/rename/remove preserve saved categories/rows/progress and both task drafts, then successful retry publishes the result. |
| All-days removal and usage | Pass: count includes earlier completed and yesterday unfinished assignments. Removal changes only the matching association, preserving tasks, fields, order, daily progress, and yesterday count. A real temporary SQLite-backed state regression creates/renames/removes through state, releases its connection, and verifies all three days plus the surviving category on reopen. Usage-read failure preserves daily availability. |
| Scoped errors and recovery | Pass: blank/multiline/General/duplicate names, missing IDs, order exhaustion, command errors, and full-read errors have distinct boundaries. Category validation/commands and same-day read Retry retain pending task errors/text. Day rollover clears stale row-action errors/targets, keeps recoverable edit text and the independent new-task draft/add error, and loads only the new day's rows. |
| Lifecycle and consumers | Pass in hosted fixtures: calendar, wake, clock, time-zone, startup/reopen, termination and observer cleanup remain covered. Each required read failure renders unavailable menu bar progress; Retry restores the count. Existing ordering, association preservation, Quick Add draft isolation, window and command regressions pass in the final selected run. These observations do not establish actual production-interface or physical lifecycle behavior. |

Independent reviewer `/root/task4_review`, who did not author or change the implementation, returned **READY** for Task 4 continuation. It reviewed the four-file state/test/architecture/requirements diff with SHA-256 `df3032ab026269b8c3d37011afd5c247f5fe7733094559fc02497a464225f3e2`, verified 63 source/spec/config inputs before and after execution, and retained its report at `independent-review.md`. Its final fresh-host execution of the identical compiled patch passed **105/105 tests**: state (37), SQLite (23), domain (9), configuration (28), and Quick Add panel (8), using separate `review/DerivedData` and `review/focused-repeat.xcresult`.

Native test repeatability remains unresolved: the reviewer's first run failed two assertions in the unchanged `testSettingsShortcutReusesWindowAndCloseDoesNotTerminate` after Command-W; clean-base AppConfiguration passed 28/28, and the identical-patch fresh-host repeat passed 105/105. No proven pre-existing defect or established cause is claimed. The failed run, baseline comparison, and repeat remain in `review/focused-tests.xcresult`, `review/baseline-app-config.xcresult`, and `review/focused-repeat.xcresult` with logs. The READY verdict covers state-only Task 4, not complete category UI, native-system acceptance, release, or merge readiness.

The final author Debug bundle is `build/task-categories/task-004/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `b1997ddc2ef6c4bf0fbd1688f196f5eebd44a6187cf8d9dd6a2804605a04c751`; debug dylib SHA-256: `a7157692e2faf2b9d7b66785e7cb29b81183c73a176226f65c8305e116aa3445`. Reviewer artifacts have their own identity in `review/artifact-identity.json`.

Only isolated databases/defaults and fake login/hotkey services were used. No production app/data upgrade, actual category interface check, real login/hotkey registration, full-suite/Release run, remote CI, commit, push, or PR was performed for Task 4. Category draft selection/recovery, grouping/preferences, manager/selector, and actual-interface acceptance remain later cards. Historical results above retain their original scope.

## Category drafts and recovery — Task 5, 2026-10-01

Pass for Task 5's state-only automated verification. The baseline was clean `main` at `c7dd4a2bf339829ededcb22bb780b05f26422397`, which merges Task 4 (PR #37). It was verified as uncommitted changes, then committed unchanged on `feat/task-categories`, fast-forwarded to that baseline, for a pull request. Changed Swift inputs and their SHA-256 values: `DailyNotesState.swift` (`0e0d471f607d38d6b7f891a538789bb557f3f20efd11e6dde9582bd43766a4ed`), `DailyNotesStateTests.swift` (`2786258a8ce80a133170d5ba22cbec499a02256d2c489b74c9f5bd517a43fcba`), and `AppConfigurationTests.swift` (`cddf0b6b6794cf39ef258e6dcd9deefdd80405a0165c83ade25ac4fa7967b331`). Architecture and requirements describe the draft contract; this section keeps the dated evidence.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app and hosted tests with the shared MenuPocket scheme. The final run at 13:21 EDT passed **112/112 tests, zero failures or skipped**: DailyNotesStateTests (44), AppConfigurationTests (28), SQLiteNoteRepositoryTests (23), NoteDomainTests (9), and QuickAddPanelTests (8). The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-005/DerivedData \
  -resultBundlePath build/task-categories/task-005/Verified-tests.xcresult \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests test
```

The first run on the initial source failed 2 assertions in Task 4's `testFailedCategoryWritesPreserveSavedSnapshotTaskErrorsAndBothDrafts`, which expected an edit to survive removal of its own selected category. Task 5's contract cancels that edit for recovery, so the test's final assertions now check the recovery context; its failed-write preservation assertions are unchanged. That run is kept as `Initial-failed-tests.xcresult` with its log.

| Claim | Outcome and proof |
| --- | --- |
| Independent drafts and atomic save | Pass: new and edit selections are separate; an edit starts from the saved association; one `update(id:text:categoryID:)` call saves text and category, including a category-only edit that keeps ID, order, completion, and day. A successful add resets its selection to General. |
| Failure and cancellation | Pass: rejected adds/edits keep text and selection with their task error; cancelling an edit leaves the new draft intact, and cancelling the new draft clears only it. |
| Invalid selections | Pass: a selection outside the loaded catalog is never written or published; storage rejecting a loaded category publishes nothing and keeps both drafts. |
| Removal, refresh, and rename | Pass: removing a new draft's category keeps text, selects General, and shows a notice; removing an active edit's category cancels it with recovered text, ID, and the pre-removal name. A failed read changes no selection; a rename changes none. |
| Rollover and window reuse | Pass: rollover recovers edit text and category context even when the next read fails, and the new draft keeps its selection for the new day. Real `TaskWindowController` close/reopen keeps both selections. |
| Persistence and Quick Add | Pass: a temporary SQLite-backed state keeps categorized adds and a category-only edit across reopen. Quick Add still saves General and leaves the window's selections unchanged. |

Retained under ignored `build/task-categories/task-005/`: `Verified-tests.xcresult`, `verified-tests.log`, `source-hashes.txt`, and the initial failed run. The Debug bundle is `DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `d2e8a73732c449b3403a325beadaacfd63687f723186a96c364ae5b44ac36bbd`; debug dylib SHA-256: `4bc3b2fffbe033ee45ead004174df9938febf369ae21fb89c4fc4f7a18fd3c7c`.

Only isolated databases/defaults and fake login/hotkey services were used. No view changed, so no running-interface check was made. No production app/data launch, full-suite/Release run, independent review, or remote CI result is claimed for Task 5. The selector control, grouping/preferences, manager, and actual-interface acceptance remain later cards.

## Category grouping and presentation preferences — Task 6, 2026-10-01

Pass for Task 6's state-only automated verification. The baseline was clean `main` at `5e6a27a3e500c6e70c536658e7cdabab163906e0`, which merges Task 5 (PR #38); `feat/task-categories` was fast-forwarded to it and the changes were verified uncommitted. Changed Swift inputs and their SHA-256 values: `DailyNotesState.swift` (`d0f4bbcaee458931da11dfb3dce25af546eec78478581df77d84194775363fb5`), new `TaskGrouping.swift` (`c57dc713c07e6a88237ae4826df40866ac85198d97fe4a39542e6bedcd7e339d`), new `TaskCategoryPreferences.swift` (`5fe4cab582aaaa93f068944fa81c6b5bcca1bf42750d5b0f8ab5e63d1389f826`), `DailyNotesStateTests.swift` (`b0de129f0e2f85360ddf9a46fff44fe0290c33cc26e6642500ea19e4c339df4e`), `AppConfigurationTests.swift` (`5a9aef486bd6e16ba3b7c9ae78ea2b345ad131178cfebd9663e98dee2a06b4a5`), new `TaskGroupingTests.swift` (`a16ea7e110c76158b0fcb9688302e462d23b2be959c697145081a4fc93128b44`), and new `TaskCategoryPreferencesTests.swift` (`fca28b86346c7389de966cdaed3b1c71b9d536f4f4f5b47a65bcfb6ed6b6ce19`). `project.pbxproj` (`0eeda1470b19af88c090211523a73cfcccace92ac69b0fe9a83929b802ee7c97`) registers the four new files. Architecture and requirements describe the grouping and preferences contract; this section keeps the dated evidence.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app and hosted tests with the shared MenuPocket scheme. The single run at 19:14 EDT passed **125/125 tests, zero failures or skipped**: DailyNotesStateTests (47), AppConfigurationTests (28), SQLiteNoteRepositoryTests (23), NoteDomainTests (9), QuickAddPanelTests (8), TaskGroupingTests (5), and TaskCategoryPreferencesTests (5). The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-006/DerivedData \
  -resultBundlePath build/task-categories/task-006/Verified-tests.xcresult \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests test
```

| Claim | Outcome and proof |
| --- | --- |
| Group and task order | Pass: groups follow saved creation order regardless of catalog input order or order gaps, then General; tasks keep saved insertion order, and a reassigned task takes its original relative position in its new group. |
| Populated groups only | Pass: an empty day has no groups; an unused category has no group but stays in the catalog; General appears last only when populated and needs no category row. |
| Counts | Pass: group counts include completed and collapsed rows and sum to the daily progress through collapse, reassignment, rename, and removal; rename keeps the group identity and its collapsed state. |
| Last-used category | Pass: only a saved new task from Today records it (including General); cancelled, rejected, and unavailable drafts, edits, and Quick Add leave it unchanged. It survives a new owner. |
| Pruning | Pass: a failed read prunes nothing; a complete read or committed removal forgets missing categories and keeps unused categories and General; a failed removal changes nothing. |
| Defaults safety | Pass: missing and malformed values read as General or expanded without being rewritten; the preferences envelope and onboarding keys are unchanged. Collapse changes are observable. |

Retained under ignored `build/task-categories/task-006/`: `Verified-tests.xcresult`, `verified-tests.log`, `build-for-testing.log`, and `source-hashes.txt`. The Debug bundle is `DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `0e2e08e5ec14186efa9646869c3be004e54cf9d792ef9e2e0077a28fc99cf6d5`; debug dylib SHA-256: `8527b8db2857f6f9dfc65224ec596712525283ca6116113b1c4fdd5604be321e`.

Hosted tests share the app's sandbox container, so `UserDefaults.standard` there is the user's real domain. Every test state with a successful read used an isolated defaults suite; after the run, the real domain still held only its preferences and onboarding keys. Only isolated databases/defaults and fake login/hotkey services were used. No view changed, so no running-interface check was made. No production app/data launch, full-suite/Release run, independent review, or remote CI result is claimed for Task 6. The grouped checklist, selector control, manager, and actual-interface acceptance remain later cards.

## Grouped Today checklist — Task 7, 2026-10-01

Automated verification is partial; the user's manual running-interface checks on an isolated fixture passed and are recorded in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md#grouped-today-checklist--task-7-2026-10-02). The baseline was clean `main` at `7ca74e6601aa4645b93e8a13412d1eed01ab0d7b`, which merges Task 6 (PR #39); `feat/task-categories` was fast-forwarded to it and the change was verified uncommitted. The only changed Swift input is `TaskWindowView.swift` (`5d88e12e2b86b579fdd48666dee965cffbb0a035840d9d9e86099a8162b6982f`). It renders `DailyNotesState.groups` as collapsible sections, binds their disclosures to `TaskCategoryPreferences`, and restores focus to a group header when a row is hidden. No test, project, or other source file changed. Architecture and requirements describe the view contract; this section keeps the dated evidence.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app with the shared MenuPocket scheme. A single hosted run of the same seven classes as Task 6 finished at 23:59 EDT. It executed 125 tests: **123 passed and 2 assertions failed**, with none skipped. DailyNotesStateTests (47), SQLiteNoteRepositoryTests (23), NoteDomainTests (9), QuickAddPanelTests (8), TaskGroupingTests (5), and TaskCategoryPreferencesTests (5) all passed. In AppConfigurationTests, 27 of 28 tests passed. The failing test was `testSettingsShortcutReusesWindowAndCloseDoesNotTerminate`: lines 456 and 460, where Command-W left the Settings and task windows visible. That is the same unchanged test and the same two assertions recorded above as unresolved native repeatability in Task 3 and Task 4 reviews. Its lifecycle fixture repository is empty, so the window shows the empty state and the new group code does not run. No isolated rerun was made, and no cause is claimed. The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/task-categories/task-007/Focused-tests.xcresult test \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests
```

| Claim | Outcome and proof |
| --- | --- |
| Build | Pass: Debug build of the shared scheme. |
| Projection, counts, order, and preferences that the view consumes | Pass: Task 6 grouping and preference tests, plus state and SQLite tests, rerun unchanged. |
| Window reuse, presentation, and deletion guards | Pass, except the native Command-W test above. |
| Groups match the projection; complete and text edits move no rows; collapse keeps counts | Pass, reported by the user's manual fixture observation. |
| Hidden rows leave Tab traversal; focus returns to the header, Add, or Retry | Pass, reported by the user's manual fixture observation. |
| Empty, all-completed, only-General, many-group, long-text, and 600 × 400 layouts, light and dark | Pass, reported by the user's manual fixture observation. |

An isolated interface fixture was prepared: `build/task-categories/task-007/GroupedChecklistFixture.app`, bundle ID `local.menupocket.task007.fixture`. It runs the unchanged production state, controller, and view over an in-memory repository and the defaults suite `local.menupocket.task007.fixture.categories`. The first fixture build crashed at launch because its suite name equaled its bundle identifier, for which `UserDefaults(suiteName:)` returns nil; only the fixture was renamed and rebuilt. Fixture source SHA-256 is `4c520c01e1d1f5535a1ffbd3b6b17f3c06e91820b2592e833de8d4ee36d05729`, and its executable is `b5762422b917fc30d5fcf2cc3a1e5278f2fb539903faba81b049780b747f0bb9`. It is non-sandboxed and never opens `notes.sqlite`. Claude did not exercise it, because the Screen Recording grant needed for Computer Use was declined. The user ran the scripted checks manually and reported that all of them passed.

Retained under ignored `build/task-categories/task-007/`: `Focused-tests.xcresult`, `focused-tests.log`, `debug-build.log`, `source-hashes.txt`, `artifact-hashes.txt`, the fixture source, and `fixture-build.log`. The Debug bundle is `build/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `224d2d827ef5113871166856f59a445df0eabe4a3eb98aabdedbbbe6062a8e0d`; debug dylib SHA-256: `9071b5159308e1ddf147fcfdf27fe5e8f099ce3139c43cbb0eff1877c0c69c21`. Only isolated databases/defaults and fake login/hotkey services were used. No production app/data launch, full-suite/Release run, independent review, or remote CI result is claimed. The category selector, manager, and final actual-interface acceptance remain later cards.

## Category composer selector — Task 8, 2026-10-02

Automated verification is partial; the user's manual running-interface checks on an isolated fixture passed and are recorded in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md#category-composer-selector--task-8-2026-10-02). The baseline was clean `main` at `0170dbfc89025f2e7d5e53dbf74906a39669c028`, which merges Task 7 (PR #40). `feat/task-categories` was fast-forwarded to it, and the change was verified uncommitted. Changed Swift inputs, by SHA-256:

| File | SHA-256 |
| --- | --- |
| `MenuPocket/Notes/TaskWindowView.swift` | `3c1c347acfc2ae2d274e594cc930fbb2f5fc0084142d2ae79992891d7bdfbcc1` |
| `MenuPocket/Notes/DailyNotesState.swift` | `21a1b5fbcde0624cab3a6ae9e89c0f4be0269dcf4191959a892b2e2d595ff1c6` |
| `MenuPocket/Notes/TaskGrouping.swift` | `ef4debeaf5791c7a003767dd8f55a200bb7c8fe58e05267dbf5375f2ffc13dd7` |
| `Tests/MenuPocketTests/AppConfigurationTests.swift` | `68ac46411ba3b08366695be058223fde3670f777a4befb76e7ab07306921ad1e` |
| `Tests/MenuPocketTests/DailyNotesStateTests.swift` | `297b21adb685c34145e262f65a32e02e386e1aa214f4885eaa012bd8441949cb` |
| `Tests/MenuPocketTests/TaskGroupingTests.swift` | `1c74e0a08dde2d1d897efa47620b3d308d49666c2b69383f441ebd5dea279d05` |

The composer now has two rows: the task field, then a Category picker bound to `draftCategoryID`/`editCategoryID`, with Save and Cancel. The picker lists saved categories in creation order and then General. `DailyNotesState.startNewDraft()` selects the saved last-used category or General, and the view calls it only when it opens a hidden composer with empty new-task text. A successful `addDraft()`, or a `saveEdit()` that changes the category, expands the destination group. `TaskGroupID(categoryID:)` maps nil to General. The recovery notice shows a recovered edit's category. The project file, `AppDelegate`, `TaskWindowController`, Quick Add, and the legacy panel did not change.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app and tests with the shared MenuPocket scheme. A single hosted run of the same seven classes as Task 7 finished at 00:56 EDT. It executed 128 tests: **126 passed and 2 assertions failed**, with none skipped. DailyNotesStateTests (49), SQLiteNoteRepositoryTests (23), NoteDomainTests (9), QuickAddPanelTests (8), TaskGroupingTests (5), and TaskCategoryPreferencesTests (5) all passed. In AppConfigurationTests, 28 of 29 tests passed. The failing test was again `testSettingsShortcutReusesWindowAndCloseDoesNotTerminate`, at lines 515 and 519, where Command-W left the Settings and task windows visible. These are the same unchanged assertions recorded above for Tasks 3, 4, and 7. They moved 59 lines only because a new test was inserted above them. No isolated rerun was made, and no cause is claimed. After the run, the app's real sandbox defaults domain still held only its preferences and onboarding keys, last modified 2026-09-30. The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/task-categories/task-008/Focused-tests.xcresult test \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests
```

| Claim | Outcome and proof |
| --- | --- |
| Build | Pass: Debug build and test build of the shared scheme. |
| A new draft starts from a saved last-used category, otherwise General; a missing remembered ID never becomes a selection; starting a draft leaves an edit's selection alone | Pass: `testNewDraftStartsFromSavedLastUsedCategoryOrGeneral`. |
| General saves as nil, including with saved categories | Pass: the same test plus Task 5/6 state tests. |
| A successful add or category change expands only the destination; text-only edits, rejected saves, and Quick Add change no disclosure | Pass: `testSavedAddOrReassignmentExpandsOnlyItsCollapsedDestination`. |
| Through the real view and menu: Command-N seeds once; repeated Command-N and close/reopen keep the selection; Return saves text and category together and expands the destination; Escape discards a changed selection without remembering it | Pass: `testComposerStartsNewDraftsFromLastUsedCategoryAndKeepsAPendingSelection`. |
| Failed saves keep text and selection; removed categories fall back or recover | Pass: Task 5 state tests, rerun unchanged. |
| Window reuse, presentation, and deletion guards | Pass, except the native Command-W test above. |
| Layout at 600 × 400 with a long category name, dark mode, and edit selection | Pass, reported by the user's manual fixture observation; also an offscreen render (below). |
| Picker keyboard traversal, Up/Down, Return/Escape with the picker focused, native editing | Pass, reported by the user's manual fixture observation. |
| Seeding, pending selection, failure, removal, rename, day change, destination expansion, and relaunch in the running interface | Pass, reported by the user's manual fixture observation. |

A layout self-check rendered the production `TaskWindowView` offscreen, never on screen, through `ComposerSnapshot` (source `9359a3efddc26f217b28df518975181191e4d4afc39613eba506323e5f7ba905`). It used an in-memory repository and a throwaway defaults suite. The PNGs show both composer rows inside the 600 × 400 minimum, a long name truncated before Save and Cancel, readable dark mode, and an edit starting from its saved category. Offscreen rendering does not establish focus, keyboard, or interaction behavior.

An isolated interface fixture was prepared: `build/task-categories/task-008/CategoryComposerFixture.app`, bundle ID `local.menupocket.task008.fixture`, executable SHA-256 `c902138fe87ab903ba819bae49df899d89e39cab2ea7aeb2d6e261ceca93f0da`. It compiles the production `MenuPocket/Notes` sources with an in-memory repository (`FixtureRepository.swift`, `ab807b7a7a68bec4307c89d6d6b6c622656daac53d09bf241b89014564feb091`) and the defaults suite `local.menupocket.task008.fixture.categories`. The fixture source is `CategoryComposerFixture.swift` (`09a9547e05371241de85453bf58807e4ffeadf798fdeccfb30cd8a95d8bc768d`). Its menu adds Command-N, write and read failures, category removal and rename, next day, and a remembered-category readout. It is non-sandboxed and never opens `notes.sqlite`. Claude did not drive it.

The first fixture build (executable `9dfa8b525f22ab2f40615bdcf3a161864da71ecce2dbe2fc7adc28f5242b9725`) was defective. Its fixture menu put Remove School on Command-X ahead of the Edit menu's Cut, so Command-X in the text field removed the category instead of cutting text. Its write-failure commands gave no visible state. During the user's first pass, an edit save failed with the expected inline error, keeping its text and selection, because simulated write failure was still on. A reseed then moved the edit into recovery with its category, also as designed. Only the fixture was rebuilt. Fixture-only commands now use Option-Command; Fail Writes and Fail Reads are checkmarked toggles; and the window title shows the simulated failures, day offset, and the last command's outcome. A menu self-test, run without showing a window, confirmed every fixture shortcut sends its own item and that no Command key combination is shared. That self-test also cleared the fixture's own defaults suite, never the app's.

Retained under ignored `build/task-categories/task-008/`: `Focused-tests.xcresult`, `focused-tests.log`, `debug-build.log`, `source-hashes.txt`, `artifact-hashes.txt`, the fixture and snapshot sources and builds, and `snapshots/`. The Debug bundle is `build/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `fee2fba9ffb80a11c62521ceb83fd7df9b924d1dfd2e120c0da35a109204ce1a`; debug dylib SHA-256: `b9fad895e0464056642bf46196d42813e5512e9b2e47edd7cc3d319acef4a5d2`. Only isolated databases and defaults and fake login and hotkey services were used. No production app or data launch, full-suite or Release run, independent review, or remote CI result is claimed. The category manager and final actual-interface acceptance remain later cards.

## Category manager — Task 9, 2026-10-02

Automated verification passed, and the user's manual running-interface checks on an isolated fixture passed; they are recorded in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md#category-manager--task-9-2026-10-02). The baseline was clean `main` at `515e376eee3859dc45721c2b3ff47afa3b6c8b65`, which merges Task 8 (PR #41). `feat/task-categories` was fast-forwarded to it, and the change was verified uncommitted. Changed inputs, by SHA-256:

| File | SHA-256 |
| --- | --- |
| `MenuPocket/Notes/TaskCategoryManagerView.swift` (new) | `b4f8d4d6448c0c8fc7a6bbdd41fd77c578cc477a593cba0f8bb22e5101569698` |
| `MenuPocket/Notes/TaskWindowController.swift` | `62dff45936e6e77055899134af79071e43e7688d0958b68c0da01407233043e5` |
| `MenuPocket/Notes/TaskWindowView.swift` | `fd0bfa2b7b6df4c7b7111eddf30e73551159c6679b60ed95c38a0c77a3a6ec5a` |
| `MenuPocket/Notes/DailyNotesState.swift` | `ab0a042d769658e1ed7326f14921e4afbbe7baa4133a2cee9486c4f3502ce78b` |
| `MenuPocket/App/AppDelegate.swift` | `08531b07c1f3599390d4e772b62134aea609dedb4974a89227f2b156226d4d56` |
| `Tests/MenuPocketTests/AppConfigurationTests.swift` | `5b0677dbcab15d85886b0aed654e4e1e3905454df493e0187a8443a0176cb21f` |
| `MenuPocket.xcodeproj/project.pbxproj` | `9f6a22fd478b6bf6db0c4a7f8c58af622576240ff7d84a2b22706f5dd6e8c9ae` |

Today has a Manage categories… button that opens `TaskCategoryManagerView` as a sheet attached to the Today window. `TaskWindowPresentation` owns whether the manager is open and the pending removal: `canAddTask` is false while the manager is open, `requestDeletion` is ignored then, and `canManageCategories` refuses an edit, a deletion confirmation, or unavailable data but allows a pending new-task draft. Removal reads the all-days count before showing a confirmation, consumes that confirmation before writing, rechecks the category and count, asks again with the new count if it changed, and needs a fresh confirmation after a failure. `AppDelegate.validateMenuItem` now uses `canAddTask`, so Command-N is disabled behind the sheet. `DailyNotesState.clearCategoryIssues()` lets a reopened manager start without old messages. The project file registers the new view.

Xcode 27.0 (`27A266a`) on arm64 macOS 26.6.2 (`25G83`) built the Debug app and tests with the shared MenuPocket scheme. After the user approved it, a single hosted run of the same seven classes as Task 8 finished at 12:50 EDT. It executed 132 tests: **all 132 passed**, with none skipped. AppConfigurationTests (33), DailyNotesStateTests (49), SQLiteNoteRepositoryTests (23), NoteDomainTests (9), QuickAddPanelTests (8), TaskGroupingTests (5), and TaskCategoryPreferencesTests (5). The native Command-W assertions in `testSettingsShortcutReusesWindowAndCloseDoesNotTerminate` that failed in the Task 3, 4, 7, and 8 runs passed in this run; that test did not change. One passing run does not resolve their recorded repeatability question, and no cause is claimed. After the run, the app's real sandbox defaults domain still held no category keys and was last modified 2026-09-30. The command was:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/task-categories/task-009/Focused-tests.xcresult test \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests
```

| Claim | Outcome and proof |
| --- | --- |
| Build | Pass: Debug build and test build of the shared scheme. |
| Removal starts only in the open manager from the all-days count; Cancel leaves everything; a changed count asks again without writing; the confirmation is consumed before the write; a failure keeps the category, assignments, and draft and needs a fresh confirmation; success moves every day's tasks to General with unchanged progress and yesterday count, and a pending draft keeps its text but falls back to General with a notice and a cleared last-used category | Pass: `testCategoryRemovalConsumesConfirmationRechecksCountAndRequiresFreshConfirmationAfterFailure`. |
| A missing category or unavailable data cancels a pending confirmation; a failed count shows none; closing the manager cancels it; reopening clears old category messages | Pass: `testCategoryRemovalCancelsForMissingOrUnavailableTargetsAndClosedManager`. |
| Through the real window and menu: no manager over an edit or a deletion confirmation; the attached sheet opens over a pending draft; Command-N validation, Add, and deletion are blocked behind it; Escape in its name field closes only the sheet; a reopened sheet starts without the discarded name; closing Today dismisses the sheet and its pending removal and keeps the draft | Pass: `testCategoryManagerSheetBlocksTaskCommandsAndKeepsTheNewTaskDraft`. |
| Through the real sheet: Return creates a category and clears the field; reserved (" general ") and duplicate ("SCHOOL") names show a field error and stay in the field | Pass: `testCategoryManagerSheetCreatesCategoriesAndKeepsInvalidNamesForCorrection`. |
| Name rules, catalog commands, removal across all days, and selection fallback | Pass: Task 1–5 domain, SQLite, and state tests, rerun unchanged. |
| General row, rename, removal copy and focus, changed-count reconfirmation, keyboard traversal, unavailable state, layout at 600 × 400, dark and light | Pass, reported by the user's manual fixture observation. |

An isolated interface fixture was prepared: `build/task-categories/task-009/CategoryManagerFixture.app`, bundle ID `local.menupocket.task009.fixture`, executable SHA-256 `b4c97d2d586be393dd391bf567c50d7d7606a74e2dd92d132c154e34e4704d5d`. It compiles the production `MenuPocket/Notes` sources in Swift 6 mode with an in-memory repository (`FixtureRepository.swift`, `090f841c310a04c9ad3cb817d31a99790c4f89b1f701f43d8c980ce465227b66`) and the defaults suite `local.menupocket.task009.fixture.categories`. The fixture source is `CategoryManagerFixture.swift` (`2fe54ce9c34f1993c53f8bc99db5df56608162e9599351c9ee9b0b5c29bc97f5`). Its seeded School category has tasks today, yesterday, and on an older day. Option-Command fixture commands toggle write and read failures, add an older School task to change the all-days count, close the Today window directly, advance the day, and show all saved data. A menu self-test, run without showing a window, confirmed every fixture shortcut sends its own item; the only shared combination reported was the system's own Emoji & Symbols entries. The fixture is non-sandboxed and never opens `notes.sqlite`. Claude did not drive it.

Retained under ignored `build/task-categories/task-009/`: `Focused-tests.xcresult`, `focused-tests.log`, `debug-build.log`, `test-build.log`, `source-hashes.txt`, `artifact-hashes.txt`, and the fixture sources, build log, and app. The Debug bundle is `build/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`. Executable SHA-256: `fa9e6902095aba3827ddb56190b63155672c7f64ca5e896ced0053362c6dd4ba`; debug dylib SHA-256: `601b172d221bd38b8452bf88951189fa958ba4bc2ae48b9e0021b90ac1bd7174`. Only isolated databases and defaults and fake login and hotkey services were used. No production app or data launch, full-suite or Release run, independent review, or remote CI result is claimed. Integrated regression and final actual-interface acceptance remain TASK-010 and TASK-011.

## Integrated category regressions — Task 10, 2026-10-02

**Pass for TASK-010 automated verification. TASK-011 actual-interface acceptance remains Not tested.** Source: `feat/task-categories` at `0c30448326ce7cc5cbb6686d5f7e2ddcb70c47e1`, initially clean. The verified dirty Swift inputs add two cross-layer tests to `DailyNotesStateTests.swift` and four identity/draft assertions to the existing hosted manager test in `AppConfigurationTests.swift`. Production source and project configuration are unchanged. `source-inputs.json` records SHA-256 for all 49 Swift/project/scheme/entitlements inputs, and the hashes were checked again after testing and both final builds.

The focused change review covered the nine category commits (`c215205`, `847cea8`, `683f62d`, `d2fd21e`, `e65017c`, `411898c`, `9bdbd81`, `0ed73d9`, `0c30448`), including the migration, transactions, shared snapshot, Note reconstruction and fake paths, grouping/preferences, composer, manager and native command guards. No product defect requiring repair was found. Category commits do not modify Settings, login-item services or `QuickAddPanelController`; unrelated Quick Add commits in the broader branch history were excluded from this scope. This was a focused review by the executing agent, not an independent pre-push review.

Xcode 27.0 (`27A266a`), macOS 26.6.2 (`25G83`), SDK `macosx27.0`, arm64 test host, shared `MenuPocket` scheme:

| Check | Result and retained evidence |
| --- | --- |
| Focused category/lifecycle verification | **134/134 Pass**, zero skipped, seven classes, `Focused-tests.xcresult`, `focused-summary.json`, `focused-tests.log`. |
| Full existing hosted suite | **219/219 Pass**, zero skipped, 15 classes, `Full-tests.xcresult`, `full-summary.json`, `full-tests.log`. |
| Final Debug build | Pass, arm64, `debug-build.log`. |
| Final Release build | Pass, universal arm64/x86_64, `release-build.log`. |
| Migration and schema protection | Pass: existing SQLite tests exercise fresh/v0/v1 upgrade, preserved rowids/fields/counts, migration rollback/retry, v2 reopen, newer/incompatible/incomplete schema rejection and foreign keys. |
| SQLite reopen plus grouped presentation | Pass: `testSQLiteGroupsAndPresentationPreferencesSurviveReassignmentAndReopen` releases the first state/connection, reopens SQLite, and checks complete notes, categories, group identities/names/order/counts, unused-category omission, last-used category and collapsed groups. A completed reassigned task keeps its original relative position. |
| Failed reassignment/removal plus saved progress | Pass: `testSQLiteRejectedReassignmentAndRemovalKeepGroupsProgressAndSavedRowsUntilRetry` injects real SQLite AFTER-trigger failures. Atomic edit and all-days removal roll back; groups, counts, completion/day fields, drafts and preferences remain saved values. Removing the triggers permits retry, then reopened SQLite retains the committed results across today/yesterday/older days. |
| Manager guards and reused window | Pass: the existing hosted manager test also checks identical controller/window/state and selected category after closing Today with a sheet/removal pending and reopening it. |
| Unavailable reads and stale actions | Pass: the full suite retains complete-snapshot failure/retry, category invalidation, recovered text/selection, rollover, day/wake/clock/time-zone notification and stale deletion/edit checks using isolated clocks/notifications/fakes. |
| Production preservation | Pass: `notes.sqlite` and the real sandbox defaults plist have identical SHA-256, size and modification time before/after the tests. No production app/data launch or live fixture seeding occurred. |
| Whitespace | Pass: `git diff --check`. |

The initial sandboxed test build failed before tests at `ObservationMacros.ObservableMacro`/`swift-plugin-server`. The authorized Xcode build succeeded; only that authorized artifact was tested. The unchanged Command-W assertions passed in both focused and full runs. Earlier dated failures remain preserved; these runs do not establish their historical cause.

Commands, from the checkout (all outputs under `build/task-categories/task-010/`):

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-010/DerivedData \
  SDK_STAT_CACHE_ENABLE=NO build-for-testing

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-010/DerivedData \
  -resultBundlePath build/task-categories/task-010/Focused-tests.xcresult \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/NoteDomainTests \
  SDK_STAT_CACHE_ENABLE=NO test-without-building

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-010/DerivedData \
  -resultBundlePath build/task-categories/task-010/Full-tests.xcresult \
  SDK_STAT_CACHE_ENABLE=NO test

# Executed separately with Debug and Release.
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/task-categories/task-010/DerivedData \
  SDK_STAT_CACHE_ENABLE=NO build
```

Both final bundles are under `build/task-categories/task-010/DerivedData/Build/Products/{Debug,Release}/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0`, build `1`. `codesign --verify --deep --strict` passes for both; sandbox entitlements remain enabled. This is a local ad hoc build, with no publishing or distribution claim.

| Artifact | SHA-256 |
| --- | --- |
| Debug executable | `c06907212137fcfea5af2f2c65263b4667e6827d3d2becf3a0f32599d1b8d474` |
| Debug dylib | `5334fa510f6ed912a3b7be6ea79130b963589f6ab8cff01e9d83e1543c438d56` |
| Release executable | `44be4b613e633b6f4eb777dc34d1c588987036848a9ccf31f2d30080ec703f41` |
| Isolated fixture executable | `a5108843f39fecd9ca9828a2cfd93e88fa341396eb24fa3470ed691eda2d74a7` |

TASK-011 preparation: `CategoryRegressionFixture.app`, bundle ID `local.menupocket.task010.fixture`, compiles the unchanged production views/state/controller/delegate/Settings/status item with an isolated SQLite file per scenario and defaults suite `local.menupocket.task010.fixture.categories.<scenario>`. The fixture is non-sandboxed and injects fake login/hotkey services. Six deterministic scenarios (`mixed`, `empty`, `general`, `many`, `completed`, `legacy`) passed headless seed/read and a second actual-process reopen with identical saved IDs/rows. The legacy scenario starts at v1 and opens at v2; this supports fixture readiness only. No fixture window was opened or visually inspected in TASK-010.

Retained supporting records include `reviewed.diff`, source/artifact/fixture identity JSON, both xcresults and summary JSON, build/test logs, signature/entitlement information, before/after preservation hashes, fixture source/build recipe, and per-scenario seed/reopen logs and SQLite files. The local handoff is `plan/task-categories/evidence/task-010.md`. No real production migration, genuine login/day/wake, VoiceOver, final interface acceptance, independent review or remote CI result is claimed. TASK-011 is ready; TASK-012 remains dependent on its outcomes.

## Category removal repair (2026-10-02)

The subsequent feature review reproduced a valid 775-character category name clipping the all-days notice and both buttons in the fixed-size removal sheet. The repair puts the complete name in its own scrolling region and keeps the notice and action footer outside it. No name limit, persistence rule, confirmation rule, permission, dependency, or Settings behavior changed. README ordering/category instructions, grouped-layout requirements, architecture, and documentation links were synchronized; full feature acceptance remains partial.

Reviewed source: `main` at `7be53da0c4fd3cb5a64bf381ecb15afb5103ddff` plus the uncommitted `TaskCategoryManagerView.swift` repair and documentation changes. The repaired view's SHA-256 is `73406faf370270262ab9b13259108ebec42ab289844362373b5bb3a793d41a98`; all 49 Swift/project/scheme/entitlements inputs are retained in `build/category-fix-20261002/source-hashes.json`.

Fresh verification on Xcode 27.0 (`27A266a`), macOS arm64:

- Debug hosted build/test action: **Pass, 219/219 tests, none skipped**, using the shared `MenuPocket` scheme. Result: `build/category-fix-20261002/Fix-tests.xcresult`; log: `tests.log` in the same directory.
- Release shared-scheme build: **Pass**; log: `build/category-fix-20261002/release-build.log`.
- Debug, Release, and isolated fixture signatures: **Pass**, `codesign --verify --deep --strict`.

Both Xcode commands used `-project MenuPocket.xcodeproj -scheme MenuPocket -destination 'platform=macOS' -derivedDataPath build/category-review-20261002/DerivedData`, with Debug `test` and Release `build`. The test action also used `-resultBundlePath build/category-fix-20261002/Fix-tests.xcresult`.

| Artifact | SHA-256 |
| --- | --- |
| Debug executable | `e3524a6d5316b00bfbcdd125ed05fa0f5bdc4cb5e4fdba3e6d8fbe4139833128` |
| Debug dylib | `b9e8c525972e7b7f753b4e31e61c6f2d14cea27d22d52df7055aed38038880a8` |
| Release executable | `e7dc1dcfcdec54e564dcd95bb9a92b0316d798df4293242edd9b7db79d8a302d` |
| CategoryFixFixture executable | `6e5cddd4ed25d2b050341de8665948bd0fc0ba1782d2be05018d18d2838a13c7` |

Native fixture observations and saved-data comparisons are recorded in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md#category-removal-repair-2026-10-02). Tests use isolated repositories/defaults and the hosted app skips production delegate initialization. No production app/data upgrade, login registration, real hotkey registration, or GitHub action was performed. Historical evidence above retains its original scope.

## Soft Focus presentation — Task 1, 2026-10-03

**Pass for the Task 1 automated scope.** Source: `main` at `31f9e38db80e3461c54b5a6b509357c415fee8ed` plus the uncommitted `TaskWindowView.swift` presentation change (SHA-256 `bc85bab8576e71992289904dd8106ec930f97cbc9ec209def2d254199ef1d3aa`). State, grouping, storage, controllers, and service logic remain unchanged.

The shared `MenuPocket` scheme's Debug build/test action passed **94/94 focused tests, zero failures or skips** on macOS 26.6.2 arm64 with Xcode 27.0 (`27A266a`). Suites: `TaskGroupingTests`, `TaskCategoryPreferencesTests`, `DailyNotesStateTests`, and `AppConfigurationTests`. The initial sandboxed attempt could not launch Swift macro plugins; the successful run used the required host permissions. A subsequent surface-contrast fix was rebuilt and the same suites passed again against the final source.

Command: `xcodebuild -quiet -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/soft-focus-task-001/DerivedData -resultBundlePath build/soft-focus-task-001/Final-focused-tests.xcresult -only-testing:MenuPocketTests/TaskGroupingTests -only-testing:MenuPocketTests/TaskCategoryPreferencesTests -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/AppConfigurationTests SDK_STAT_CACHE_ENABLE=NO test`.

The built Debug app is `build/soft-focus-task-001/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle `local.menupocket.app`, version `0.1.0`, build `1`. Executable SHA-256: `cf2c9bea0cde55e5f33b75d69fce0ad4f883545b71a9f9d7079b7c695cbc5fde`; debug dylib: `02fcbec98553ffcd76de58ef5643f3a6eb136586341f6f24cf0c9954d3c7be8e`. This production-identity build was not launched against saved user data.

Retained under ignored `build/soft-focus-task-001/`: final xcresult/log/summary, source hashes, artifact identity, isolated fixture source/build recipe, and the mixed fixture's saved-row inspection. That inspection retains rowids 1–6 and task IDs/order after completion/uncompletion; only disposable fixture category naming and collapse preferences were changed for layout checks. [Native Task 1 observations](DESKTOP_TASK_ACCEPTANCE.md#soft-focus-header-and-grouped-list--task-1-2026-10-03) provide the separate interface proof. Full-suite/Release/remote-CI results and final Soft Focus acceptance are not claimed here.

## Soft Focus composer and row menu — Task 2, 2026-10-03

**Pass for TASK-002's focused automated scope.** Source: `main` at `19f7d7a97be54f04284db7a0b01cf6206c19e6e6` plus the uncommitted view/test/documentation changes. Final `TaskWindowView.swift` SHA-256: `5c8393bc4ab0c3669674a38881a3773e73178a23914eb1648736620fafb2143c`. The composer now sits above the list, row actions use a native Edit/Delete… menu, and focus restoration prefers stable task/group IDs. State, repository, schema, ordering, controllers, and services are unchanged.

The shared `MenuPocket` scheme's Debug build/test action passed **85/85 tests, zero failures or skips**, on macOS 26.6.2 arm64 with Xcode 27.0 (`27A266a`). Suites: `DailyNotesStateTests` and `AppConfigurationTests`. The new hosted test inserts text through the native field editor, repeats Command-N, closes/reopens the retained window, verifies the same undo manager, undoes/redoes the pending draft, and checks that nothing was saved. Existing draft/category, failed-write/recovery, deletion guards, and category-sheet lifecycle checks also pass.

Command: `xcodebuild -quiet -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/soft-focus-task-002/DerivedData -resultBundlePath build/soft-focus-task-002/Keyboard-final-tests.xcresult -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/AppConfigurationTests SDK_STAT_CACHE_ENABLE=NO test`.

An intermediate menu anchor updated a SwiftUI binding when it mounted, and the existing category-sheet close/reopen test failed twice. The same test passed against an isolated Task 1 view in the same environment. Replacing that binding with a weak, non-observed reference fixed the focused check; both affected suites passed after the final keyboard/menu changes. The failed and baseline xcresults remain under `build/soft-focus-task-002/`.

Retained evidence includes `Keyboard-final-tests.xcresult`, `keyboard-final-tests.log`, its summary JSON, final source hashes, fixture build recipe/source, artifact identity, process-exit checks, and before/after/relaunch saved-row comparisons. The Debug test host does not initialize the production delegate or saved user database. [Native Task 2 observations](DESKTOP_TASK_ACCEPTANCE.md#soft-focus-composer-and-row-menu--task-2-2026-10-03) are separate interface evidence. No full-suite, Release, remote CI, production-data upgrade, or final integrated Soft Focus acceptance result is claimed.


## Soft Focus Settings and category sheet — Task 3, 2026-10-04

TASK-003 changes presentation in `SettingsView.swift` and `TaskCategoryManagerView.swift` on clean `main` at `9ee9def`, with the change set uncommitted. Settings uses scrolling inset sections and a fixed Quit footer; the category list and removal name use semantic inset surfaces, and restored row focus scrolls into view. Controller lifetimes/sizing, bindings, state, schema v2, ordering, preferences, and services are unchanged. No production Swift file or test was added.

Final production source SHA-256:

| Input | SHA-256 |
| --- | --- |
| `MenuPocket/Settings/SettingsView.swift` | `ac39fa70c28c668c7d846d8d88ccc35dd0389fd41bb974f0d3643b56e628e642` |
| `MenuPocket/Notes/TaskCategoryManagerView.swift` | `3adf1b919ce68b46ae55b44f2023fc5a8eba623b27f2657e1cba585c0e621dcc` |

The initial author build/test run passed **113/113 tests, zero failures or skips** with the shared MenuPocket scheme, Debug, arm64 macOS 26.6.2 (`25G83`), and Xcode 27.0. This run preceded the final category focus-scroll correction; it is supporting evidence, not a final-source automated acceptance claim. The restricted-shell attempt failed because Swift macro plugin services could not run; the host-authorized run succeeded.

The independent reviewer built the final source and passed build-for-testing. Its first 113-test run had two assertion failures in `testComposerKeepsNativeUndoAcrossRepeatedRequestsAndWindowReopen`. A clean `9ee9def` baseline passed the same 113 tests, and a fresh test session with the identical compiled patch then passed **113/113, zero failures**. Independent native undo/redo after reopening also passed. The cause of the first failure remains unproven; it is not classified as a baseline defect. All three runs are retained under `build/soft-focus-task-003/review/`: `Focused-tests.xcresult`, `Baseline-focused-tests.xcresult`, and `Focused-tests-rerun.xcresult`, with their corresponding logs. The reviewer reported no code finding after its static and core native checks. Extra verification was stopped after the user's time/usage feedback; an independent corrupt-warning observation and final READY verdict were not completed. Task 3's author-operated acceptance remains separate from that incomplete review.

Author command: `xcodebuild -quiet -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/soft-focus-task-003/DerivedData -resultBundlePath build/soft-focus-task-003/Host-focused-tests.xcresult -only-testing:MenuPocketTests/AppConfigurationTests -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/LoginItemSettingsTests -only-testing:MenuPocketTests/AppModelTests SDK_STAT_CACHE_ENABLE=NO test`.

Independent final-source rerun: `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/soft-focus-task-003/review/DerivedData -resultBundlePath build/soft-focus-task-003/review/Focused-tests-rerun.xcresult -only-testing:MenuPocketTests/AppConfigurationTests -only-testing:MenuPocketTests/LoginItemSettingsTests -only-testing:MenuPocketTests/AppModelTests -only-testing:MenuPocketTests/DailyNotesStateTests test-without-building`.

The final isolated fixture compiled in Swift 6 mode and all four prepared variants passed ad hoc signature verification. Its source is `build/soft-focus-task-003/SoftFocusFixture.swift`, SHA-256 `7a2ca34005aef53b3757899018c38f1746d161f721becc5f678b534e4d1cc01b`; the argument list, final source hashes, build log, signed artifact identities, test log/summary, and xcresults are retained under ignored `build/soft-focus-task-003/`. Normal/corrupt/protected variants were operated; the empty variant was prepared but not operated by the author. [Native Task 3 observations](DESKTOP_TASK_ACCEPTANCE.md#soft-focus-settings-and-category-sheet--task-3-2026-10-04) are separate evidence. No full-suite, Release, remote CI, genuine system registration, production-data upgrade, or final integrated Soft Focus acceptance is claimed.

## Soft Focus integrated UI — Task 4, 2026-10-04

**Pass for the final focused Debug build/regression scope.** Source was clean `main` at `962c47e4ca6b24b0bf0dc9f3fa3fc86ad34a8678`, containing Tasks 1–3. No production or test source changed during Task 4. Review of the combined change from `31f9e38` found no schema, repository, ordering, movement, controller, or service changes; `git diff --check` passed. Current layout/action guidance already matched the final source.

The shared MenuPocket scheme built the Debug app and hosted test bundle and passed **123/123 tests, zero failures or skips**, with arm64 macOS 26.6.2 (`25G83`) and Xcode 27.0 (`27A266a`), finishing at 13:29 EDT. Suites were `TaskGroupingTests`, `TaskCategoryPreferencesTests`, `DailyNotesStateTests`, `AppConfigurationTests`, `LoginItemSettingsTests`, and `AppModelTests`. Native undo across retained-window close/reopen passed in this run; Task 3's earlier failure retains its unproven cause. An existing QoS runtime warning remains in the result without a test failure.

```bash
xcodebuild -quiet -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/soft-focus-task-004/DerivedData \
  -resultBundlePath build/soft-focus-task-004/Focused-tests.xcresult \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskCategoryPreferencesTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/LoginItemSettingsTests \
  -only-testing:MenuPocketTests/AppModelTests SDK_STAT_CACHE_ENABLE=NO test
```

The built app is `build/soft-focus-task-004/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle `local.menupocket.app`, version `0.1.0`, build `1`. Executable SHA-256: `520e8dcedd39bf71d92d95efd67b93bfb3a86b23326738e14790e511e09a102e`; Debug dylib: `6bc297d32b02290caee1e215333c5de2314f95ec96e95e4fcea4fde7c213aec9`. This production-identity artifact was not launched against user data.

The unchanged Task 3 native harness was freshly compiled against all current production inputs in Swift 6 mode. Mixed, empty, many, and completed bundles passed ad hoc signature verification and were operated separately. All input hashes still matched after native verification. Logs, xcresult/summary, fixture source/build arguments, full source hashes, artifact/process identities, and relaunch comparisons remain under ignored `build/soft-focus-task-004/`. [Task 4 native observations](DESKTOP_TASK_ACCEPTANCE.md#soft-focus-integrated-ui--task-4-2026-10-04) establish the separate interface result. Full-suite, Release, remote CI, production-data upgrade, and genuine system acceptance were not run; their historical gaps remain open.

## Mouse and keyboard focus visibility — 2026-10-04

Debug build passed with the shared `MenuPocket` scheme. The focused shared-scheme run passed **57/57**, zero failures/skips: `AppConfigurationTests`, `QuickAddPanelTests`, `TaskGroupingTests`, and `LoginItemSettingsTests`. Results are `build/keyboard-focus/Focused-tests.xcresult` and `test-summary.json`; build/test logs are `build/keyboard-focus-build.log` and `build/keyboard-focus/tests.log`. No new tests were added.

The change adds `KeyboardFocusVisibility` and registers it in the app target, gates the existing Today/category/legacy focus outlines, and suppresses native non-text focus effects in mouse mode across Today, category management, Settings, and both retained panels. Editable fields and first-responder restoration are preserved. Source and artifact hashes are in `build/keyboard-focus/source-and-artifact-hashes.json`. Debug executable SHA-256: `1c6aca20995039cf769c074b98a6482969c4d42fee4fa840b0875ab022619465`. Native interaction evidence is recorded in the corresponding acceptance section.


## Inline task editing — 2026-10-04

The shared `MenuPocket` Debug scheme built successfully and the final focused run passed **91/91**, zero failures/skips: 35 `AppConfigurationTests`, 51 `DailyNotesStateTests`, and 5 `TaskGroupingTests`. The new hosted test exercises native Return on a rejected inline edit, draft/data preservation, Escape cancellation, and restoration of an independent Add draft. Result: `build/inline-edit/Focused-tests-v4.xcresult`; log: `build/inline-edit/focused-tests-v4.log`.

Source is based on `main` HEAD `8f3804734f58b8c89ea24b08ba64d8ab8a98b3ee` with this task's uncommitted UI/test/requirements changes. Pre-existing `AGENTS.md` and `docs/WORKFLOW.md` edits were preserved. Toolchain: Xcode 27.0 (27A266a). `TaskWindowView.swift` SHA-256: `af3dedefb085ce686d73063654223f4b1e79595e2090918082872b291108fa00`; test file: `3f834a635b93f35c9a8af9dab5da09b241a6c75031084fa0e0a27c385287b4cf`. Exact hashes/build arguments remain in `build/inline-edit/artifact-identity.json` and `fixture-build-command.json`.

The first run had four assertion failures during the new asynchronous field-restoration check and existing native text-command checks. After waiting for the restored Add field, the next run passed 91/91. Native verification then exposed pending-Add focus stealing after a distant category reassignment, an offscreen editor on re-entry at minimum size, and a focused but offscreen saved destination. The final fix has one reveal/focus owner, mounts the destination group at the top, then centers the target row. The final v4 run passed 91/91. Earlier runs and logs remain historical evidence only.

The isolated 100-task fixture uses current production views/state/delegate, a separate SQLite/defaults suite, a simulated October 3 clock, and fake login/hotkey services. Its executable SHA-256 is `f60913f519dc25dabb9be7044b4bf8c2ee963b6a74030ecdafd753e70a7cad61`; harness SHA-256 is `fe306466d70eb9eef77bf73d0eac6b30de590020b0dc46c0c3a4373f1da8a2fc`. See [native observations](DESKTOP_TASK_ACCEPTANCE.md#inline-task-editing--2026-10-04). No persistence schema, repository behavior, permissions, dependency, Add workflow or Delete workflow was changed. Full-suite, Release, remote CI and production/system acceptance were not run for this change.


## Movement contract and pure ordering — 2026-10-06

Task 1 adds a pure movement planner and UUID-based request/placement/outcome types in [TaskMovement.swift](../MenuPocket/Notes/TaskMovement.swift), with [contract tests](../Tests/MenuPocketTests/TaskMovementTests.swift) registered in the shared Xcode project. It supports before/after and end-of-group placement, validates expected day/source and destination/anchor identities, preserves task fields and every other task's relative order, and returns unchanged for equivalent visible positions. Malformed/stale snapshots reject without mutation. The planner's changed result is only a proposal; repository persistence and state/UI integration remain future work.

Source baseline: branch `feat/task-movement`, HEAD `34b789f2333b7f53dfabfb38b472617ce13cab4e`, initially clean tracked tree. Dirty build inputs were the new planner/tests and project membership. Schema remains v3 and daily reads remain rowid ordered. Today and Quick Add share `DailyNotesState.add(text:categoryID:)` → `SQLiteNoteRepository.add(_:)`, the sole production daily INSERT. Later-to-Today transfer still throws unsupported. The next ordering migration must guard Later-table creation by `version < 3`; v4 is available at this baseline. No real database, defaults, login registration, or hotkey was changed.

The final shared-scheme Debug hosted run passed **13/13**, zero failures: 8 `TaskMovementTests` and 5 existing `TaskGroupingTests`. Xcode 27.0 (27A266a), macOS arm64 destination. Command:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -only-testing:MenuPocketTests/TaskMovementTests \
  -only-testing:MenuPocketTests/TaskGroupingTests test
```

The initial run also passed 13/13; the final run rebuilt a simplified preservation assertion. Final result: `build/DerivedData/Logs/Test/Test-MenuPocket-2026.10.06_13-56-53--0400.xcresult`; logs and hashes: `build/task-movement-task1/`. Planner SHA-256: `e4efe76d39df5b51f1c6b823be04bcb35e2a40faa159b8261bbe133d6bc0543d`; tests: `5ac08559712ed3223f51aff9486567d4251a9da5410129af15967840134f6258`; project: `8799d183976677b2b32413718df57a28a7e42714a81136d26848f354b0dcf812`. Debug host executable: `7b066f5ad1c069f4ac6b91f0c31e79892f673224ce9a29381e5e82786d3e7d40`; Debug dylib: `69b96b120b35f294b90635a350830efbc019f0250c55bea93568521acfe253fe`. Project plist validation and `git diff --check` passed.

Cleanup: the only temporary app created was this checkout's `build/DerivedData/Build/Products/Debug/MenuPocket.app`. After both completed runs, no process was running from that path. It was unregistered and moved with `FileManager.trashItem` to `/Users/nstn/.Trash/MenuPocket.app 13-57-36-795.app`, then unregistered again after LaunchServices re-registration was observed. Final LaunchServices dump contains neither original nor Trash path; Spotlight lists neither temporary copy. The pre-existing main-checkout Debug executable hash was identical before/after cleanup. Another session's Later worktree host was preserved. Cleanup evidence is in `build/task-movement-task1/cleanup.log`, `launchservices-after.txt`, `spotlight-after.txt`, and `main-app-before.txt`/`main-app-after.txt`.

This is focused automated contract evidence. No SQL migration, repository move, persisted ordering, visible drag/menu behavior, full-suite, Release, remote CI, or native/system acceptance is claimed for Task 1.

## Daily ordering migration — 2026-10-06

Movement Task 2 introduces SQLite v4 in [SQLiteNoteRepository.swift](../MenuPocket/Notes/SQLiteNoteRepository.swift): additive integer `notes.display_order`, per-day rowid backfill, unique `notes_day_display_order_idx(day_key, display_order)`, and schema/integrity/order validation before advancing the version. Category/Later steps are guarded by their original versions. Fresh stores and independent historical v0/v1/v2/v3 fixtures verify preserved task fields/rowids, interleaved assigned days/categories, completion, category catalog and Later rows. Index-name failure after backfill proves schema/data/version rollback and safe retry for every historical version. Sparse ranks survive byte-identical reopen; future v5 and malformed indexes/noninteger/negative order are refused without repair.

Minimal append allocation was pulled forward from Task 3 so repeated Add and Quick Add remain valid under the new unique index. It uses the existing write transaction; Int64 exhaustion throws without a write. Task 3 still owns ordered reads/runtime rank validation, overflow compaction and the persisted move command. Reads remain rowid ordered; no visible movement/state action or Later transfer was implemented.

Source baseline: `feat/task-movement`, HEAD `801eb96bf1bc1b505444613e2fa50d8342b05a96`, initially clean tracked tree. Dirty executable inputs: repository and repository tests only. Xcode 27.0; macOS 26.6.2 (25G83), arm64. The shared-scheme Debug hosted run passed **92/92**, zero failures/skips: 33 `SQLiteNoteRepositoryTests`, 51 `DailyNotesStateTests`, 8 `QuickAddPanelTests`.

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests test
```

Result: `build/DerivedData/Logs/Test/Test-MenuPocket-2026.10.06_14-12-00--0400.xcresult`. Logs, summary, source/artifact hashes and cleanup evidence: `build/task-movement-task2/`. Initial sandboxed invocation failed in Xcode macro/test services; the authorized invocation above passed. Repository SHA-256: `f691b4f0da2fedfd140827f224de0137385223b76e255ab70a4757bfb1b9a0ca`; tests: `5ac0bc0dd5ab5a17f649f8256d956b609522fd0955538733bf620c7de51d34e3`. Host executable: `b08651d19c51aeaca3058f0e91f37ddc3839a7b8192c72563f834389b5afac75`; Debug dylib: `715b51f4fe966128540b9aca4ae3ac1e3f92452b1fa70485ce5339ed6b632d1d`. Diff whitespace check passed.

Cleanup: no test host process remained after testing. The only created temporary app, this checkout's `build/DerivedData/Build/Products/Debug/MenuPocket.app`, was unregistered and moved with `FileManager.trashItem` to `/Users/nstn/.Trash/MenuPocket.app 14-12-44-475.app`. Following automatic Trash-path re-registration it was unregistered again; final LaunchServices dump contains neither path, Spotlight contains neither temporary copy, and the original bundle is absent. Main-checkout Debug executable hash remained `8ee2320cf524a802568da6aad47209d84a7cf3d9e18ddce406e0a54caf3a1c67` before/after.

This establishes isolated migration and focused regression evidence. No production database upgrade/launch, native movement interaction, oldest-OS run, full suite, Release, remote CI, or system acceptance was performed.


## Atomic repository movement — 2026-10-07

**Pass for Movement TASK-003 repository handoff; independent review READY.** Baseline: clean `feat/task-movement`, HEAD `c121808`; final source/tests/workflow were uncommitted. SQLite schema remains v4. The repository now reads validated saved `display_order`, executes UUID-based explicit moves against a fresh transaction snapshot, rewrites ranks in two passes and updates the moving category atomically. Changed snapshots return only after COMMIT. Rejected/equivalent moves perform no UPDATE. Add/Quick Add compact only an exhausted day's ranks inside the insertion transaction. Existing Edit/completion and surviving delete/category-removal ranks are retained; Later→Today remains unsupported.

Xcode 27.0 (`27A266a`), macOS 26.6.2 (`25G83`), arm64. Author and fresh independent reviewer runs each passed **112/112**, zero failures/skips: 40 SQLite repository, 51 DailyNotesState, 8 Quick Add, 8 movement planner, 5 grouping. Both used the shared MenuPocket Debug scheme and isolated databases/injected services. The initial sandboxed author invocation failed because Swift macro/test services were blocked; the permitted rerun below succeeded.

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -only-testing:MenuPocketTests/SQLiteNoteRepositoryTests \
  -only-testing:MenuPocketTests/TaskMovementTests \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests \
  -only-testing:MenuPocketTests/QuickAddPanelTests test
```

Coverage establishes exact order after fresh repository reopen for within/cross-group, before/after and empty/General movements; preservation of rowids/task fields, other days, Later, categories and counts; rejected/stale/no-op requests with an UPDATE-rejecting trigger; rollback after writes in both rank passes and category reassignment; reader-lock **COMMIT/SQLITE_BUSY** failure followed by retry on the same connection; Add after move; Edit/completion/delete/category removal rank retention; Int64-exhaustion compaction with failed-insert rollback; and runtime malformed/noninteger/duplicate/negative ranks rejected without repair.

Author xcresult: `build/DerivedData/Logs/Test/Test-MenuPocket-2026.10.07_10-13-24--0400.xcresult`. Independent xcresult: `build/DerivedData/Logs/Test/Test-MenuPocket-2026.10.07_10-15-08--0400.xcresult`. Logs and hashes: `build/task-movement-task3/` (`tests.log`, `tests-authorized.log`, `independent-review-tests.log`, `source-hashes.txt`, `artifact-hashes.txt`). Repository SHA-256: `ff6b8378d075c141c9666ea7cd22d6fd5ea6ba82449435194aa1138a4024dc9c`; repository tests: `77cff607aff4188a0c330f6748ef55b83d9b900c5b508a4eadca3991d04273bb`. Debug executable: `98f1ebd3ba7cf5e0e0a33322134986bae8bec2ba47b239291af8fc5f2664a2a6`; Debug dylib: `ec76e491e956c3b869fd68d1dc63876ea2cb331fb60d0c6c9bc1791498f22c50`. Independent reviewer `/root/review_task3` did not author the changes. Final implementation/test snapshot remained stable through review; subsequent edits record handoff/evidence only.

Cleanup: no process remained at this checkout's exact test-host path. `build/DerivedData/Build/Products/Debug/MenuPocket.app` was unregistered and moved using `FileManager.trashItem` to `/Users/nstn/.Trash/MenuPocket.app 10-16-13-486.app`. Unregistering that Trash path reported scan `-10814`; the final LaunchServices/Spotlight dumps contain neither original nor Trash path. The original bundle is absent. `/Applications/MenuPocket.app` executable SHA-256 is identical before/after. Evidence: `processes-before-cleanup.txt`, `trashed-app-path.txt`, `launchservices-after.txt`, `spotlight-after.txt`, `main-app-before.txt` and `main-app-after.txt` under the log directory. Diff whitespace validation passed.

This is repository/automated evidence. State move command/guards, drag/menu interaction, native changed-data relaunch, production database upgrade, 1,000-task scale, oldest-OS run, full-suite, Release and remote CI remain later-card or separate evidence. No real saved database, defaults, login registration or global hotkey was changed.


## Guarded state movement — 2026-10-07

- Scope: TASK-004 only, branch `feat/task-movement`, base/HEAD `559658ffb628ce5bafd58e1d7227d68f70b653e5` plus uncommitted changes to daily state, retained presentation/controller, write-error copy, state tests, and architecture guidance. No schema, repository, drag source/target, or movement-menu implementation changes.
- Contract: `DailyNotesState.moveTask(_:) -> TaskMoveOutcome?` validates action-time day and displayed task/category/anchor expectations, checks shared presentation guards, and delegates to the cached repository. Only committed `.changed` publishes rows and expands the destination. `.unchanged` never changes collapse state; rejection reports `.move`; nil denotes guards/unavailability/write failure. Read `.load` takes presentation precedence over retained move failure, and explicit Retry restores readiness. Only `.changed` authorizes later UI reveal.
- Tests: six new state tests cover committed publication, completion/progress/task-field/draft/recovery/last-used preference preservation, destination-only expansion, write failure/retry, unavailable-read recovery, unchanged/stale/removed task/category/source/anchor requests, inline edit/delete/category manager/termination guards, rollover, and isolated SQLite refresh/fresh-repository reopen. Existing state/status-item, Quick Add, and app configuration regressions remain included.
- Command: `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/task4/DerivedData -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/QuickAddPanelTests -only-testing:MenuPocketTests/AppConfigurationTests test`.
- Result: **100/100**, zero failures/skips (57 daily state + 8 Quick Add + 35 configuration). Xcode 27.0 (27A266a); macOS SDK 27.0. Log: `build/task4/tests.log`; result: `build/task4/DerivedData/Logs/Test/Test-MenuPocket-2026.10.07_10-28-44--0400.xcresult`. `git diff --check` passed. Initial sandbox run failed with the Observation macro-plugin malformed-response/access failure; retained in `build/task4-tests.log`, then rerun with permitted access.
- Author test binary SHA-256: `962d2360807b09ce31d5585f3a98d8cf318db2ebc8e8f1b59b25f33f517e6630` (recorded in `build/task4/app-sha256.txt`). Cleanup after both failed and successful runs: temporary hosts at `build/task4/DerivedData/Build/Products/Debug/MenuPocket.app` were unregistered, moved to Trash, and their Trash paths unregistered; records `build/task4/failed-trash-path.txt` and `build/task4/trash-path.txt`. No session-created app remains under `build/task4`; no host process remained; Spotlight and LaunchServices expose no original host path. `/Applications/MenuPocket.app` retained the same inode and modification time (`241915164`, `1791325693`). No production database/defaults or genuine login/hotkey services were used for movement verification.
- Evidence limits: these are hosted automated state/integration checks. Native move error interaction, drag/menu movement, scrolling/reveal, macOS 14, Release/full-suite/remote CI, and real-user data acceptance were not performed; later feature cards own integrated acceptance.

- Independent review: fresh reviewer `/root/review_task4` found no actionable Task 4 defect. Its rebuilt run passed all 57 state and 8 Quick Add tests and 32/35 configuration tests; three existing native configuration tests failed with seven assertions: composer undo, native text select/paste, and Settings/window close. Isolated rerun reproduced those assertions, and an unchanged HEAD baseline reproduced the **same three tests/seven assertions**. This establishes a pre-existing failure in that execution environment, not a Task 4 regression. The author's 100/100 run remains separately recorded above; the review run is not described as entirely green. Logs: `build/task4/review-rebuild-tests.log`, `build/task4/review-native-isolated.log`, `build/task4/review-baseline-native.log`; final identity and reviewer cleanup: `build/task4/review.md`. Review verdict: **READY for Task 4 state handoff**, with native movement acceptance deferred and broader native-test instability retained as a limitation.

## Native movement source — 2026-10-07

Task 5 source implementation only; the user explicitly deferred tests. No XCTest or native UI interaction was run. Task 6 drop destinations and saved-drop routing are absent, so this does not establish native movement acceptance.

- Source: `feat/task-movement`, HEAD `8d90c1c60042a7088ba5f2b37ecf06161faa658e`, with Task 5 changes in `TaskDragSource.swift`, `TaskWindowView.swift`, `TaskWindowController.swift`, `DailyNotesState.swift` and app project membership. Existing Task 4 changes were present at the start and were retained; HEAD advanced to this Task 4 commit during the session without this task issuing a commit.
- Final source SHA-256: `TaskDragSource.swift` = `d9f562e0512abc3578ee784b3f2270a09f5fcbb327887dc9736ee6dc1d19b4aa`; `TaskWindowView.swift` = `6424f8ceba88754d96a7f7fd27614a70f9cc4290e04ecefd57a02d4d800c8bd5`.
- Build: Xcode 27.0 (27A266a), shared MenuPocket scheme, Debug, macOS 14 deployment target. `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -derivedDataPath /private/tmp/menupocket-task5-build CODE_SIGNING_ALLOWED=NO build` passed for the final source. Log: `/private/tmp/menupocket-task5-build-final.log`. This compile-only unsigned app was never launched.
- Initial sandboxed build failed with Swift macro-plugin malformed responses, including Observation/Preview macros. The authorized build outside the sandbox passed; logs are `/private/tmp/menupocket-task5-build.log` and `/private/tmp/menupocket-task5-build-unrestricted.log`. No source repair was needed for that environmental failure.
- Static: project plist validation and `git diff --check` passed. Installed SDK headers expose the native source-end and source-operation callbacks and the drag-session source API for the supported deployment target. References: [NSDraggingSource](https://developer.apple.com/documentation/appkit/nsdraggingsource), [native session creation](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)). This is compilation/API evidence, not a macOS 14 runtime observation.
- Cleanup: the exact temporary `/private/tmp/menupocket-task5-build/Build/Products/Debug/MenuPocket.app` was unregistered, moved through `FileManager.trashItem` to `/Users/nstn/.Trash/MenuPocket.app 10-46-02-749.app`, and that Trash path was unregistered. Original bundle path is absent; process and LaunchServices checks found no app at the original temporary path. Cleanup log: `/private/tmp/menupocket-task5-cleanup.log`. No production app/data/defaults or system registrations were changed.
- Not tested: handle start, preview/cursor, Escape/outside/rejected/successful drag endings, cleared observable session state in the running interface, checkbox/text selection/copy/ellipsis coexistence, oldest supported macOS runtime. These are pending native feasibility/acceptance checks; do not infer them from the build.

## Movement destinations — Task 6 (2026-10-07)

Source: `feat/task-movement`, HEAD `792e2645306c52c21c881717c2f63e380c5791e7` plus the Task 6 changes in `TaskDragSource.swift`, `TaskGrouping.swift`, `TaskWindowView.swift`, new `TaskDropTarget.swift`, project membership, and state/grouping tests. Partial destination changes existed at task start and were retained/finished. No persistence schema or repository change.

Shared-scheme Debug verification on macOS 26.6.2 (25G83), Xcode 27.0 (27A266a): **74/74 passed**, zero failures/skips, selecting `TaskGroupingTests`, `TaskMovementTests`, and `DailyNotesStateTests`. Command:

```sh
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/menupocket-task6 \
  -resultBundlePath build/task6/Tests-final.xcresult \
  -only-testing:MenuPocketTests/TaskGroupingTests \
  -only-testing:MenuPocketTests/TaskMovementTests \
  -only-testing:MenuPocketTests/DailyNotesStateTests test
```

New callback tests exercise both row halves, one-shot dispatch despite duplicate callbacks, external/self/no-op rejection, a guard changing between hover/drop, header placement into a collapsed empty category, and failed-write preservation of saved rows/drafts/collapse/error plus feedback cleanup. The grouping test checks transient empty categories/General, creation order and unchanged counts/normal presentation. These use isolated repositories/defaults and fake dragging info; they do not simulate the native drag loop.

The first sandboxed run failed on Xcode Observation macro service access; a permitted rerun found test-fixture protocol conformance errors, which were corrected before the successful final run. Evidence: ignored `build/task6/tests*.log`, `Tests*.xcresult`, `test-summary.json`, fixture source/build commands/logs, crash report and artifact hashes.

Independent reviewer `/root/review_task6` did not author or modify this patch. Fresh focused verification passed **9/9** (three callback tests plus grouping), project plist and whitespace checks passed, no demonstrated source defect. Verdict **BLOCKED** for unresolved native acceptance. Reviewed code identity: tracked diff SHA-256 `c9a503e0b68b59d3549421e3822804e45899243d234a03f36ecda08ef89f075d`; untracked `TaskDropTarget.swift` SHA-256 `2496c73a3ec672d137d2c12063e1fdffef3a698d6008c66b9bcaf53a686b49ed`. Reviewer logs/results: `/private/tmp/menupocket-task6-review-permitted.log` and `/private/tmp/menupocket-task6-review/Logs/Test/Test-MenuPocket-2026.10.07_11-15-54--0400.xcresult`. Later documentation edits do not change that code snapshot.

Cleanup completed after failed/successful sessions: author's exact Debug host and native fixture were unregistered, moved with `FileManager.trashItem`, and Trash paths unregistered; reviewer did the same for their host. Original paths are absent. Final author's process/LaunchServices checks expose neither original host nor fixture; Spotlight has no fixture. `/Applications/MenuPocket.app` executable hash is identical before/after. Cleanup/identity records are under `build/task6/`. No production data/defaults, login/hotkey registrations, Git publication, full suite, Release build, oldest-supported-OS acceptance or later-card scrolling/menu acceptance was performed.


## Movement scrolling and reveal — Task 7 (2026-10-07)

Source: `feat/task-movement`, HEAD/base `ee29e716339a8654319c4790bceb05c6d9ce59c6`, plus changes to `DailyNotesState.swift`, `TaskDragSource.swift`, `TaskWindowController.swift`, `TaskWindowView.swift` and `DailyNotesStateTests.swift`. Final code/test diff SHA-256: `69960471bf43d5feba42a34b168fa96090256536ba1e459253f7337f307112ad`. Documentation changes follow verification; no schema/repository change.

Shared `MenuPocket` scheme Debug build and focused tests on macOS 26.6.2/Xcode 27.0: **69/69 passed**, zero failures, selecting `DailyNotesStateTests` and `TaskGroupingTests`. Command: `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/TaskGroupingTests -resultBundlePath build/task7/Tests-verified.xcresult test`. Logs and results are retained under ignored `build/task7/`.

New checks observe bounded clip scrolling, source unmount survival, cancellation preventing further scrolling and reservation lasting until native end; edge/center/outside geometry; saved reveal supersession and cancellation by newer Add/deletion while preserving drafts. Existing callback failure coverage additionally verifies absence of a failed-save reveal. These are isolated hosted/state checks, not real drag-loop proof.

Initial sandbox build failed on compiler macro access; permitted rerun passed 69/69. A later timer-lifetime refinement failed Swift 6 region isolation, then was corrected and the final suite passed 69/69. Failed outputs remain retained, and partial bundles were cleaned between sessions.

Fresh independent reviewer `/root/task7_review` did not author or modify production code. Final independent `test-without-building` checks passed **6/6**, zero failures/skips (`build/task7/review-tests-verified.log`, `ReviewTests-verified.xcresult`). Reviewer verified the final diff identity and whitespace; no remaining actionable source defect. A source-group focus fallback/reveal risk identified during review was corrected before final verification. Verdict **BLOCKED** for required native observations and the Task 6 prerequisite. No full suite, Release, remote CI, macOS 14 runtime or production-data acceptance is claimed.

Every temporary Debug host and native fixture, including failed-build bundles, was unregistered/trash-moved and Trash paths unregistered. Original paths are absent; exact fixture processes exited. Main `/Applications/MenuPocket.app` executable SHA-256 remains `2f230e6c4b43243e55f56fc0b2e166664daa20e63bf60c4b55b101d707582f9f`. Cleanup logs: `build/task7/failed-cleanup.txt`, `cleanup-first.txt`, `cleanup-compile.txt`, `cleanup-final.txt`. The initial failed host's Trash path was also unregistered during final cleanup. No production storage/defaults, login-item or hotkey services were changed.

## Native movement source verification — Task 5 (2026-10-07)

Source: `feat/task-movement`, HEAD `0502d41f1612e4ba19bddaed70b16be868c51864`, plus six new drag-source lifecycle tests in `DailyNotesStateTests.swift`. No production source change.

Shared `MenuPocket` scheme Debug on macOS 26.6.2, Xcode 27.0: **69/69 passed**, zero failures/skips, selecting `DailyNotesStateTests`. Command: `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/task5/DerivedData -resultBundlePath build/task5/Tests.xcresult -only-testing:MenuPocketTests/DailyNotesStateTests test`. Log: ignored `build/task5/tests.log`.

New checks: one reserved token per eligible Today task, with foreign source-end ignored; begin refused behind inline edit, deletion confirmation, category manager, termination and unavailable read; payload validation accepts only the exact live source with one private item/token and rejects another handle, external source, unmatched token, generic text, extra representation, bulk items, a mid-drag guard and a cancelled token; invalidation on source-group change and day rollover; one-shot consume, with cancel/close/termination clearing feedback while the native reservation lasts until source end; handle start requires enabled state and a ≥4 pt drag, is reset by mouse-up/unmount, and never takes keyboard focus. Hosted tests cannot create a real `NSDraggingSession`; native lifecycle evidence is in [Task 5 acceptance](DESKTOP_TASK_ACCEPTANCE.md#native-movement-source--task-5-2026-10-07).

Cleanup: the `build-for-testing` host and the final test host at `build/task5/DerivedData/Build/Products/Debug/MenuPocket.app` were unregistered, moved with `FileManager.trashItem`, and their Trash paths unregistered (`build/task5/cleanup-build-for-testing.txt`, `build/task5/cleanup-final.txt`). `/Applications/MenuPocket.app` executable SHA-256 is unchanged (`2f230e6c4b43243e55f56fc0b2e166664daa20e63bf60c4b55b101d707582f9f`).

## Row-menu movement — Task 8 (2026-10-07)

Source: `feat/task-movement`, HEAD `ecd9cbc` (row-menu Move Up/Down/To, minimal-scroll reveal repair, three new menu tests). Shared `MenuPocket` scheme Debug on macOS 26.6.2, Xcode 27.0: **86/86 passed**, zero failures/skips (72 `DailyNotesStateTests`, 6 `TaskGroupingTests`, 8 `TaskMovementTests`). Command: `xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug -destination 'platform=macOS' -derivedDataPath build/task8/DerivedData -resultBundlePath build/task8/Tests.xcresult -only-testing:MenuPocketTests/DailyNotesStateTests -only-testing:MenuPocketTests/TaskGroupingTests -only-testing:MenuPocketTests/TaskMovementTests test`. Log: ignored `build/task8/tests.log`.

New checks cover menu destinations in catalog order with the current group checked and unavailable, boundary-disabled Move Up/Down within a group, saved up/down/Move To results that preserve completion, progress and expansion, guards (inline edit, deletion confirmation) and unknown tasks, and request equality with drop routing for the same placement. The run also re-verifies the Task 5–7 drag/drop/reveal tests after the shared reveal change. Native evidence: [Task 8 acceptance](DESKTOP_TASK_ACCEPTANCE.md#row-menu-movement--task-8-2026-10-07).

Cleanup: the test host was unregistered, moved with `FileManager.trashItem`, and its Trash path unregistered (`build/task8/cleanup-tests.txt`); the build-for-testing host was cleaned earlier (`build/task8/cleanup-build-for-testing.txt`). This session never wrote to `/Applications/MenuPocket.app`. Its executable hash was `2f230e6c…` through the 17:18 fixture cleanup; it was replaced at 17:27 outside this session (now `716fe6cc…`), before this test run.

## Integrated movement regression and scale probe — Task 9 (2026-10-07)

Source: `feat/task-movement`, HEAD `400ef7577773bebb711a6569831faeb75cc39d51`, plus two new tests in `DailyNotesStateTests.swift` (file SHA-256 `5874d666159806669ca8bad6c25c92dee7646bba91d911e09ae0c7d575fb09b0`). No production source change. macOS 26.6.2 (`25G83`), Xcode 27.0, shared `MenuPocket` scheme, `platform=macOS`.

| Check | Result | Evidence and limit |
| --- | --- | --- |
| Full shared-scheme Debug suite | Pass | **274/274**, zero failures/skips, finished 2026-10-07 23:15:09 local. Includes all 35 `AppConfigurationTests`; the three native configuration failures seen during Task 4 did not reproduce in this run. Log: ignored `build/task9/tests.log`; result bundle `build/task9/Tests.xcresult`. |
| Integrated SQLite movement | Pass | `testIntegratedSQLiteMovementSurvivesReopenAndLaterDailyWrites`: row-menu Move Up, drop-shaped completed task into a collapsed group, Move To General, General → empty category, then an equivalent no-op. Exact order/groups, unchanged text/day/created/completed fields, unchanged progress, preserved new-task draft and last-used category, and destination-only expansion survive refresh and a fresh state/repository reopen with shared isolated defaults. After the moves it also covers Today Add (remembered category) and Quick Add-path append, category-only Edit keeping its daily rank (unlike the explicit Move To append), completion, delete, and category removal merging into General in saved order. A third reopen matches. The other-day row and the Later row are unchanged, and `moveLaterToToday` stays unsupported. |
| 1,000-task scale probe | Pass (correctness); latency recorded | `testScaleProbeMovesAndReadsOneThousandTasksAcrossCategories`: 1,000 tasks across 10 categories + General (one third completed), 20 state-level saved moves (10 worst-case same-group last→first, 10 cross-category). Each move keeps every other task's relative order with no loss or duplication. Progress is unchanged, and a fresh reopen matches. Hosted Debug (unoptimized) timings: move median **15.6 ms**, min 14.5 ms, max 16.6 ms; state read 7.6 ms; grouping 3.2 ms; one row's menu moves 1.2 ms; fresh reopen read 8.7 ms; seeding 1,000 individual Add transactions 4.0 s (about 4 ms per add). Timing is logged, not gated. |
| Debug and Release builds | Pass | `build` for both configurations succeeded (`build/task9/build-Debug.log`, `build-Release.log`). Debug executable SHA-256 `5567dfe4bd494c830953667a43365b26601f36a5fbfff969147d887df587eec2` (arm64). Release `da4c3ecfef137a5bbcb19ec1b38d14199bdc5ce9a8241429da27e80fe49e7af4` (x86_64 + arm64). Strict deep `codesign --verify` passed for both. |

The scale result supports keeping dense O(n) per-day rank rewriting. A worst-case 1,000-task move costs about one 60 Hz frame in unoptimized Debug, so no fractional ranking is needed. Whether this produces a visible stall in the native interface is a Task 10 observation; these tests do not establish it. Native drag, VoiceOver, macOS 14, minimum window, production-data upgrade and remote CI were not exercised.

Commands:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/task9/DerivedData \
  -resultBundlePath build/task9/Tests.xcresult test

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/task9/DerivedData build
```

Cleanup: the Debug test host/app and the Release app under `build/task9/DerivedData/Build/Products/` were confirmed not running. They were unregistered, moved with `FileManager.trashItem`, and their Trash paths were unregistered. No `.app` remains under `build/task9`, and neither LaunchServices nor Spotlight lists either path (`build/task9/cleanup.txt`). `/Applications/MenuPocket.app` executable SHA-256 is unchanged (`716fe6cc…`). Task 10 must build and identify its own artifact from this source.
