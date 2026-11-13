# Compact Categories UI — verification handoff

Status: implementation and focused tests complete; native acceptance remains partial. The user resumed on 2026-11-13 with a hard three-minute stop. The bounded resume rechecked source identity, retained data and cleanup evidence, and obtained the independent final scoped review below. Do not treat this document as full task acceptance.

## Requested change

Implement selected design A: content-height list, General Built-in badge, visible six-dot drag handles, direct Rename, ellipsis popover containing Remove…, header Done, labeled creation field immediately below the list. Preserve monospace, Daybook colors, validation, rename/removal guards, shared catalog semantics and data.

## Current source

- `MenuPocket/Notes/TaskCategoryManagerView.swift`: compact list measures its content and caps its height; rows wrap long names, preserve existing drag/drop state, show separators/handles, and expose the existing removal flow through a Daybook popover.
- `MenuPocket/Notes/TaskActionsPopover.swift`: opt-in keyboard dismissal hook. Escape/Tab can restore the category trigger without overriding focus after an outside click/scroll. Existing task/composer callers keep their default behavior.
- `MenuPocket/Notes/TaskWindowView.swift`: makes the existing anchor available to category popovers.
- `.agents/skills/verify-menupocket/features/categories.md`: revised recipes and identifiers.

No commit, push, PR, installation or production-data change was requested or performed. The installed `/Applications/MenuPocket.app` was preserved; its observed PID was 59449. Changes remain in the working tree on base `main@49534e985b7164e83166bfc493d8f240e0b71fd1`.

Final fixture aggregate app-source SHA256: `d31c210af07f1f15d0983e96de33f5efffafc6ef9f42db7b07d8c5d1b2dda4a1`. Recheck source identity before reusing any evidence.

## Completed verification

Agent-operated isolated fixture `20261113-153449`, fictional `basic` seed; unique database/defaults, fake hotkey/login services. Evidence root: `build/verify-menupocket/evidence/20261113-153449/`. `identity.json` binds source/bundle/executable. The fixture doctor confirmed no production database was open.

| Check | Result / evidence |
| --- | --- |
| Debug build | Pass; `build/categories-compact-build.log`. Initial sandboxed attempt failed because Swift macro plugins could not run; permitted build succeeded. |
| Final focused hosted tests | Pass: 21 total, 20 passed, 1 AX-dependent skip, 0 failures; `build/categories-compact-tests-verified.log` and its recorded xcresult. Covers manager creation/drafts/guards, category movement and preferences. Skipped test: `testCategoryManagerReordersPreserveNativeNameDraftAndRenameGuard` cannot reach SwiftUI Rename via the hosted process AX tree; corresponding native rename/cancel paths were exercised separately. |
| Independent source review/typecheck | Fresh reviewer `/root/review_categories_a`, not an author; Swift 6 all-source typecheck and diff check passed. No actionable source defect found on final source. Scratch evidence `/private/tmp/menupocket-categories-review-twelmvhj/`. Reviewer verdict remains BLOCKED pending final native evidence, physical drag, cleanup and handoff review. |
| Short list + visible handles + compact creation area | Pass; snapshot `02-outside-click-field-focus`. |
| Outside-click focus | Pass: opened Work ellipsis, clicked New category, typed Health; field retained focus and text. Snapshot `02-outside-click-field-focus`. |
| Create + duplicate | Pass: Return created Health; case-insensitive `work` duplicate kept draft and showed inline error. Snapshot `03-duplicate-inline-error`. |
| Rename/cancel/guards | Pass: Work rename canceled with Escape, new-name draft retained; Errands renamed Shopping with Return; other row/navigation actions disabled while renaming. Native CUA journey in this chat. |
| Keyboard actions/removal cancel | Pass: Tab from Rename to ellipsis, Space opened menu without selecting Remove, Escape restored trigger; Return opened menu then chose Remove; confirmation focused Cancel. Escape canceled and restored actions trigger. Snapshot `04-keyboard-removal-cancel-focus`. |
| Removal behavior | Pass for captured fields: Work removal showed scope of 4 tasks, then restored new-name field. Snapshot `05-removed-work-preserved-tasks` contains stored rows. A bounded-resume automated comparison confirms all 7 daily rows and 2 Later rows, daily IDs/rowids/text/day/order/completion/continued_on and Later rowids/text/completion, plus expected category reassignment. Exact baseline timestamps and Later IDs were absent from the saved text snapshots, so their preservation is not established by this comparison. |
| General-only | Pass after intentionally removing Shopping and Health through UI; no custom rows, explanatory empty state, creation stays near list. Snapshot `06-general-only`. |
| Long catalog + reveal | Pass: recreated Work/Errands and created Category 01–08 through UI; list scrolls, new field/Done remain visible, last inserted row revealed. Snapshot `07-many-categories`. |
| Minimum-size + very long name | Pass: real CUA corner drag reached 800-point-wide minimum (1600 × 1184-pixel screenshot, including window chrome). Created `Research ` repeated 120 times (1079 saved characters after trim). Row exceeded viewport; Rename/ellipsis remained reachable. Rename and removal cancel restored actions focus/reveal. Snapshot `08-minimum-long-name`; final raw CUA state/screenshots in this chat. Name subsequently renamed to `Learning and personal development with a long category name` through UI. |
| Light/Dark | Observed Dark at normal/minimum and Light at minimum, with app-only theme setting. Snapshot `09-minimum-light`. No global macOS theme change. |

Exploratory builds `20261113-152304` and `20261113-152959` are historical, cleaned and retained as evidence only. They exposed an invisible SF Symbol grip (replaced by explicit circles) and Escape focus returning to New category. The intermediate broad dismissal callback could override outside-click focus; final code uses keyboard-only restoration, which was rechecked natively.

## Where the session paused

The fixture was on the Categories pane in Light theme at minimum size, with Work then Errands and several additional categories. The user was asked to physically drag Errands before Work; instead they explicitly requested a pause. **No user-operated drag was reported or verified.** Do not record this as passed or as a user-approved deferral of acceptance.

Snapshot `10-paused` preserves UI/tree/defaults/rows. The stopped fixture database is retained as `paused-fixture.sqlite` under the same evidence root to preserve this disposable test state. Do not use it as production data. Temporary runnable bundles are cleaned rather than left running during the pause. Cleanup records: each run's `cleanup.txt`, `build/categories-compact-fixture-cleanup.log`, and `build/categories-compact-test-host-cleanup.json`.

## Bounded resume and independent verdict

On the user's three-minute resume, no application source changed and no app/test host was built or launched. The actual aggregate app-source hash still matches the verified fixture exactly. `git diff --check` passes. `resume-invariants.json` under the final evidence root records the automated saved-field comparison, expected Work-to-General reassignment, unchanged schema 5, and read-only `integrity_check: ok`. The saved stopped database contains 7 daily tasks, 2 Later tasks, and 11 intentionally created custom categories; all tasks are General after the intentional UI removals. A read-only SQLite reopen does not establish native app relaunch persistence.

Independent reviewer `/root/review_categories_a` rechecked the final source and retained screenshots/trees/database/cleanup evidence and issued **BLOCKED for full task acceptance**. No actionable source defect was found. The two material remaining observations are a user-operated physical manager reorder and changed-data native quit/relaunch; the user has not waived either. Other unknowns remain unavailable-state recovery, exact baseline timestamps/Later IDs, VoiceOver and production/system integrations.

The reviewer confirmed the selected A layout, visible handles, compact General-only/short lists, minimum-size long-name controls, Light/Dark screenshots, create/duplicate and focus/removal states, data preservation for captured fields, and completed cleanup. Earlier independent all-source typecheck and the 20-pass/1-skip focused tests remain applicable because source identity is unchanged. The tracked implementation diff reviewed was SHA256 `a9cc2aa87be57688fdf333360d0eb4d44fa89793466b51013f49f86a65df9e30`. This documentation update records the verdict; it does not promote it to READY.

## Resume checklist

1. Recheck working-tree/app-source identity and cleanup results. Preserve these uncommitted changes and unrelated work.
2. Rebuild an isolated fixture if needed and tie new observations to its identity. The user authorized test hosts and fixture launch in this chat; that authorization persists, but coordinate screen focus if needed. Preserve the saved evidence; never use the installed app's database.
3. Finish the physical manager drag on a disposable fixture: move Errands before Work using its six-dot handle, verify visible order and saved ranks, and preserve all task data. Repo workflow requires a physical mouse/trackpad; synthetic category drags remain inconclusive.
4. Finish changed-data quit/relaunch persistence and fresh final screenshots at normal size. Saved-field invariant comparison is complete as described above; exact baseline timestamp and Later-ID comparison cannot be recovered from text evidence that never included those values. Unavailable-state behavior is preserved in source but was not re-exercised in this session. VoiceOver and production/system integrations were not tested.
5. Send final evidence and final diff identity back to the independent reviewer for re-review. Do not promote the current BLOCKED verdict to READY yourself.
6. Clean all temporary bundles/hosts and update this handoff with actual final evidence before claiming completion. No install or GitHub action is authorized by this implementation request.
