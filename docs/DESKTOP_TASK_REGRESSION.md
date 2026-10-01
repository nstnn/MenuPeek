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
