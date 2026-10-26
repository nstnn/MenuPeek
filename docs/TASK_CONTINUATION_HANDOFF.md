# Manual task continuation — 2026-10-22

## Contract

Select unfinished tasks on a past day in History (including Yesterday and Unfinished), then press Continue today. The whole selection saves atomically. New attempts append to Today with fresh UUIDs and the action-time creation instant, retaining text/category. Source rows keep their day, UUID/rowid, timestamps/completion and saved order, and gain only `continued_on`. A historical 3/5 stays 3/5. Continued originals appear under All with a destination date, leave actionable unfinished lists/reminders, and cannot be continued again. Completing/deleting a target never changes its source.

Schema v5 adds one nullable column to v4 without rewriting rows or ranks. Known earlier schemas upgrade transactionally; incompatible layouts and version 6+ are refused. Before any real-data upgrade, follow [v5 preparation](WORKFLOW.md#schema-v5-upgrade-preparation). This change does not install a release or open the user's saved database.

## Automated verification

Evidence directory: `build/continue-today-evidence/` (ignored). Shared scheme MenuPocket, macOS destination, dedicated derived data `build/continue-today-check`.

- Initial sandbox build failed to run Swift Observation compiler plugins; a permitted build succeeded.
- First full suite: 448 executed, one old assertion failed because it assumed the former last-column layout. The assertion now compares the original saved fields explicitly.
- Final full suite: **450/450 passed**, `tests-final-clean.log`, including both new model/menu rollback regressions. The earlier 450-test run had two window-close assertions fail in the unchanged `AppConfigurationTests.testSettingsShortcutReusesWindowAndCloseDoesNotTerminate` while fixture interaction overlapped; the isolated full rerun passed without source changes. This records the observed sequence rather than claiming a proven root cause.
- A fresh independent reviewer ran 71/71 SQLite/History integration checks on the keyboard-corrected source, then 28/28 glance model/menu checks on final source. Logs: `reviewer-focused-tests-keyboard-final.log` and `reviewer-glance-final-tests.log`. The independent final verdict and exact change-set identity are retained in `reviewer-final.md` in the evidence directory.
- Added real-SQLite checks cover selected-batch order/content/category/new identities; unchanged historical fields/progress; actionable unfinished summaries/reminders; duplicate prevention after reopen/deletion; chained continuation on a later day; stale/completed/future/duplicate/empty selections; write/COMMIT rollback and retry; additive v4 migration; cross-layer publication/drafts and action-time rollover rejection.

## Native verification

User authorized native tests and isolated fixture verification in this chat. These are agent-operated observations, using seeded synthetic data and fake system services, not user-operated or production acceptance. Follow the [History recipe](../.agents/skills/verify-menupocket/features/history.md#continue-today-recipe).

Final artifact: run **20261022-123431**, base HEAD `fc2e7e7b53c050aad5b824a427abdfe8fccf762a`, app-source SHA-256 `5dd96efc1230ea11dd08a4a6818f093a765ade3876924e5ad060ac3761f0c5f9`, executable SHA-256 `42c50da5e3392a5d4b5d70adbee7317d003f9748a87aca31c385977a332d177f`. Its `identity.json`, `actions.log`, snapshots and cleanup live under `build/verify-menupocket/evidence/20261022-123431/`.

| Check | Result and evidence |
| --- | --- |
| Yesterday selection, original progress/marker, fresh Today target/count | Pass; snapshots 01–02, Today 1/4 → 1/5 while yesterday remains 1/2. |
| Today draft and yesterday reminder | Pass; actions retain `Preserve Today final` and confirm the reminder is gone. |
| Unfinished entry, real Tab/Space/Return | Pass; `tab-traversal-final.json` reaches the checkbox at Tab 4; snapshot 03 shows success, Today 1/6, old progress 0/1; index becomes empty. |
| Quit/relaunch persistence | Pass; snapshot 04 stopped and 05 relaunched `db.txt` and defaults match; saved targets/count survive without reseeding. |
| Injected backward date and glance | Pass; relaunch with Oct 21 leaves rows unchanged, preserves 1/2, disables continued-original actions and renders No unfinished tasks; snapshot 06 and `rollback-glance.png`. The Mac clock was not changed. |
| Two-task batch on final source | Pass; snapshots 07–09 show two new Oct 23 targets, source markers and unchanged Oct 22 progress 1/6; Today is 0/2. |

Intermediate evidence is retained: run 20261022-122424 found the checkbox skipped by Tab (`tab-traversal.json`) despite direct AX-focus keyboard activation working. Explicit focusability/Space/Return handling fixed it; run 20261022-123100 and the final run both observed real Tab access. The first run also captured complete before/after SQLite JSON for a two-task batch: only two source markers changed and two targets appended (`native-batch-comparison.json`). The reviewer independently reproduced and verified the correction for misleading All done copy after a backward date (`reviewer-rollback-probe/`). Filter/day selection clearing, completing a target without altering source progress and ineligible Today rows were observed on the first run; final hosted coverage and final native routes supplement that intermediate evidence.

## Cleanup and limits

All three fixture bundles/defaults/processes are cleaned by their own `cleanup.txt`; the dedicated hosted XCTest app is recoverably trashed and unregistered by exact path (`host-cleanup.json`). Final aggregate cleanup is recorded in `final-cleanup.json` under `build/continue-today-evidence/`. The user's main `/Applications/MenuPocket.app` and real saved data are preserved; no install, commit, push or PR was performed.

Real production database upgrade, installed-app sandbox behavior, real midnight/wake/time-zone transitions, real system login/hotkey behavior, VoiceOver and macOS 14 are not established by this fixture session.
Release packaging and a new minimum-window/light-theme acceptance sweep were not run for this feature. Transaction/disk-failure recovery is covered with injected SQLite/COMMIT failures in hosted tests; real disk failure UI is not claimed.
