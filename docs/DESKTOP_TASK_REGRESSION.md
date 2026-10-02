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
