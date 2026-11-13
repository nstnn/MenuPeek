# Daybook UI handoff — 2026-11-09

Typography update (2026-11-12): app-owned text now uses System Monospace. The original Georgia/serif observations below are historical; see [System Monospace acceptance](SYSTEM_MONOSPACE_ACCEPTANCE.md) for the current implementation and verification.

## Shared pane canvas — 2026-11-13

History (including Unfinished), Categories and Settings now use `DaybookPalette.canvas`, matching Today/Later in both themes. Their former system-window background and Light overlay covered the parent canvas. The rail and inset card surfaces retain their existing colors. This change only replaces the three pane backgrounds; pre-existing composer edits in `TaskWindowView.swift` and its verification recipe were preserved.

- **Pass:** shared `MenuPocket` scheme Debug build (`build/canvas-validation-build.log`); `git diff --check`. No new logic tests or full-suite run for this presentation-only change.
- **Pass, agent-operated fixture:** run `20261113-104040`, fictional `basic` data, fixed `2026-11-13T16:00:00Z` / `America/Toronto`, separate SQLite/defaults, fake login/hotkey services. Doctor confirmed the executable identity and isolated database. Sidebar navigation opened Today, Later, History, Unfinished, Categories and Settings in both Light and Dark. Screenshots show the shared canvas with readable cards and controls, including the Settings heading and footer.
- **Pass:** three unobstructed main-pane pixel positions match exactly across all six destinations within each theme (12 screenshots). Raw evidence: `build/verify-menupocket/evidence/20261113-104040/canvas-pixel-checks.json`, `snapshots/02-settings-Dark` through `13-categories-Light`, and `actions.log`.
- **Pass:** all 14 `db.txt` snapshots are byte-identical, including rowids, task/category values and schema v5. Theme was restored to System; Today and the menu bar retained `1/4` progress.
- Artifact identity: base HEAD `11784038efe55c5e2477b667feac658b3596a0c9`; dirty app sources are the three changed pane views plus the pre-existing `TaskWindowView.swift`. Source-manifest SHA256 `97827ad934af1e2fc72bcaf0a994374b118580e05ad6205212247a73dd690946`; fixture executable SHA256 `f8a2eb7e27c4b151a39ccc87a7335ad4843e56d2685b977b01f3e4a216b75248`. `identity.json` retains paths, bundle ID and Swift toolchain.
- **Pass, cleanup:** fixture stopped, trashed and unregistered; its defaults and scratch run removed. The isolated Xcode Debug bundle was also trashed and its original/Trash paths unregistered. `cleanup.txt` and `build-host-cleanup.txt` retain checks. The installed main executable SHA256 remained `8a9f58c7cb903fce476221f5d8f15fbc2b94fb7be8407b8fdc31dbc2ee9366da`.
- **Not tested:** production sandbox/system integrations, physical pointer behavior, minimum-size resizing and VoiceOver. No install, commit or push was performed.

## Original Daybook handoff

The user approved the Daybook concept and requested implementation. This is a native SwiftUI/AppKit presentation change to Today/Later, not a new task model. No installation, commit, push, or release publication is included.

## Implementation

- `TaskWindowView.swift`: warm appearance-aware paper/rail colors; Georgia date and main heading; native Today/Later control in a 218 pt rail (164 pt below 740 pt width or 480 pt height); Today-only date/progress ring/History; labeled Categories and Settings; flat category sections, row separators, muted completed text with strikethrough.
- Header, top composer/errors, footer and task list share the existing 660 pt content cap and centered column at wide sizes. Initial content remains 800 × 560 pt, minimum 600 × 400 pt. Native controls, focus handling, text selection, inline editing, Return/Escape, row menus and guarded commands are retained. The existing Add composer is shown explicitly; the browser concept's permanent input and simplified popup editor were not substituted for those production interactions.
- `TaskBrowserView.swift`: forwards the existing Settings callback. History replaces the rail and exposes Today/Later plus Settings in the native toolbar, so both lists remain reachable from the child screen.
- Existing category drag padding (12 pt top/bottom, 16 pt sides), 24 pt group spacing/drop inset, movement implementation, storage schema v5, repositories, category preferences, application preferences, login items and Quick Add services are unchanged.
- README, Requirements, Architecture and the project-local verification feature recipes describe the new control locations and presentation. Historical acceptance documents keep their original results.

## Automated evidence

Shared scheme: `MenuPocket`, macOS destination, Xcode 27.0 (27A266a), Swift 6.4, macOS 26.6.2 (25G83), arm64 machine. Tests use the production XCTest host's existing isolated/fake dependencies; they do not start production storage.

The shared serial suite passed all **450 tests**, including native field/Undo/window lifecycle, scoped Today/Later commands, category/history/movement and SQLite preservation tests. Release builds succeeded. Logs for the final column-alignment revision are `build/daybook-layout-final-tests.log` and `build/daybook-layout-final-release.log`; their `.xcresult` location is printed in the test log. Earlier full serial runs also passed 450/450.

Retained unsuccessful attempts: the initial sandboxed build could not run the Observation macro plugin; the successful checks used the compiler's required host access. The first parallel test run had three assertions fail in the single native Undo/reopen case. That case passed in isolation, and subsequent full serial runs passed. The cause of the parallel-run failure was not established; it is not relabeled as a passed run.

## Agent-operated native evidence

All interface work used uniquely identified, unsandboxed fixtures, fictional `basic` seed data, fixed `2026-11-09T16:00:00Z`/America-Toronto context, separate SQLite and defaults, and fake login/hotkey services. Doctor confirmed no production MenuPocket database was open. The user's running `/Applications/MenuPocket.app` was not driven or replaced.

Interaction run `20261109-111714` is retained under `build/verify-menupocket/evidence/20261109-111714/`. Identity: base HEAD `77034cacb4834e3a5e63e42259e5043c43e4845d`, dirty inputs the two views above, source-manifest SHA256 `9df772589aa23708e359181283020b4c7993492b7ef90c5d2a2ad9df452ee80f`, executable SHA256 `0ff4b5386e58625cf3df5c824eebe58af48be479cf7700cb9aab60737124f5de`. This run preceded only the final wide-column alignment correction; the interaction paths below were unchanged by that correction. The final alignment fixture's identity and screenshots are recorded in the closure below.

| Check | Result | Raw evidence within the interaction run |
| --- | --- | --- |
| Normal and minimum layout | Pass | `01-final-baseline`, `02-final-minimum-composer`, `04-final-minimum-edit`, `06-final-minimum-delete`; `normal-window-bounds.txt`, `minimum-window-bounds.txt` |
| Native geometry provenance | Pass | CG window bounds 800 × 592 and 600 × 432 pt after native corner dragging; the title area adds 32 pt over the controller's 800 × 560 / 600 × 400 content sizes. Screenshots are 2× pixels, not point measurements. |
| Add long text with Return, complete | Pass | CUA native click/type/Return plus snapshots 02–03, AX progress and stored row; menu count 1/4 → 1/5 → 2/5 |
| Inline edit/category assignment | Pass | 04–05: same saved task and rank 4; category General → Work after Save |
| Deletion Cancel | Pass | 06 → 07: confirmation visible at minimum size, Cancel leaves rows unchanged |
| Later semantics, write, transfer | Pass | 07–09: no Today date/progress, remaining count; Later-only add keeps Today count; Read the SQLite docs transfers to Today, menu count 2/6 |
| History/Categories/Settings | Pass | 10–12: native History toolbar destinations return to Later, category sheet opens/closes, Settings opens from rail |
| Light/Dark, long/completed text | Pass | 12–13 and 17; `final-later-light.png`, `final-today-dark.png`; long task wraps and completed rows remain in order |
| All completed | Pass | 14: AX progress `6 of 6 complete`; checkboxes and rows remain present |
| Menu Move To | Pass | 15 AX and the settled DB in 16/18 show Water the plants in Errands. Snapshot 15's DB query ran before the asynchronous write settled, so that DB file alone is not proof. |
| Confirmed deletion / empty Later | Pass | 16: two fictional Later deletions confirmed, remaining count zero and empty state; Today count unchanged |
| Changed-data quit/relaunch | Pass | 18 → 19 stopped → 20 relaunched, without reseeding; visible 2/6 and identical saved data/preferences |
| Unavailable and Retry | Pass (simulated) | 21: injected `fail-open`, unavailable state/disabled Add/count —; 22: Retry restores rows and 2/6 |
| Preservation | Pass | `preservation-checks.json`: stopped/relaunched/recovered `db.txt` and decoded preferences byte-equal. Complete defaults files were also independently compared. Schema remains 5. |

Snapshots contain `db.txt`, `defaults.plist`, `preferences.json`, `ax-tree.txt`, `window.png`. `actions.log` names the input mechanism. On an earlier revision, two background PID-key attempts left a Later field empty; CUA click/type/Return worked, and final-run AX input explicitly activated the fixture before typing and waited for the text value. Failed attempts remain recorded.

## Limits and closure

Pointer category-drag attempts on earlier run `20261109-110544` produced no saved reorder and remain **inconclusive**, not Pass. Original drag source/target dimensions were restored afterward; no drag implementation changed. Full physical task/category dragging, VoiceOver, increased-contrast settings, macOS 14, production sandbox/upgrade behavior, real login, real global hotkey and public distribution were **Not tested**. This handoff does not close historical pointer/system acceptance gaps.

### Final alignment and cleanup

Final exact-source fixture `20261109-113637`: source-manifest SHA256 `95edcad6f4efb0a6be8840cbe6874d65fae5705361e87aff8eb41036b56d1bf6`, executable SHA256 `aaf55a0f27238eabdeeedbc33fe20d03d883e3c2bb7d135caaeac27d14b2c4da`. Final view hashes are `202bd4ba8aba1c04f1257384619ecf2771eea70d0dccf39c4f9095e3befe65db` (TaskWindowView) and `25f5b24009ab00fe8fd32565e32de1e3ada492677737a6dea5dc03f9e98ba5ed` (TaskBrowserView).

- **Pass:** `01-final-aligned-normal`, `02-final-aligned-wide` and `03-final-aligned-composer` show the exact final source at normal and wide sizes. The wide frame is 1200 × 692 pt (1200 × 660 content); `wide-window-bounds.txt` records CG point geometry. Native corner drag and the observed screenshot establish the centered header/composer/list column; Save is disabled for the blank composer, while Category/Cancel remain visible. `final-wide-composer.png` retains the direct native capture.
- **Pass:** the final shared serial suite again ran 450 tests with zero failures and the final universal Release build succeeded (`daybook-layout-final-*.log`). No production changes followed these checks.
- Independent reviewer: fresh `daybook_review` agent under the code-review skill, not the implementing agent. Exact snapshot manifest and bounded readiness verdict are retained in `build/daybook-review-identity.json` and `build/daybook-independent-review.md`. This review does not certify historical pointer/system gaps.
- **Pass:** all three fixture runs were stopped, trashed and unregistered; their `cleanup.txt` files confirm no original app path, registered fixture path, defaults suite or process remains. Temporary shared-scheme Debug/Release app bundles were moved with `FileManager.trashItem`; their exact original and Trash paths were unregistered and checked absent from LaunchServices. `build/daybook-host-cleanup.txt` and `build/daybook-trashed-host-paths.txt` retain the results. One unregister invocation returned a Spotlight scan error for an already-trashed path; subsequent exact-path registry verification passed.
- The installed main app's executable SHA256 matched before/after host cleanup. The main app and saved data were not replaced. No commit, push or install was performed. The pre-existing `.gitignore` edit was preserved.
