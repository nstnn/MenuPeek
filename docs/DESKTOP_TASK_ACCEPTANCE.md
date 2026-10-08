# Desktop task interface acceptance — 2026-09-29

**Status: partial; full feature acceptance is Blocked.** This tracked record imports the Task 9 running-Release observations. The task window, native text commands, cancellation, Settings, Quit and observed saved-data relaunch passed within the scopes below. System menu bar/Dock access and safe fixture interaction were denied; material observations remain open.

The user authorized Task 10 documentation updates while asking that Task 9 be assumed completed. Task 9's actual report became available during the update and records partial acceptance. Documentation synchronization can finish under that authorization without declaring those checks passed. No tests were created or run, app rebuilt, or app/system interaction performed by the documentation update. [Desktop regression](DESKTOP_TASK_REGRESSION.md) retains the separate Task 8 automated evidence.

## Artifact and observation identity

- Task 9 source: clean tracked `main`, `52cd8e8f3a11d5e2c60494f1622978c6d8299ffe`.
- Running product: `build/desktop-task-management/task-008/Release/MenuPocket.app`; bundle ID `local.menupocket.app`; version `0.1.0` / build `1`; minimum macOS `14.0`; regular-app metadata.
- Executable SHA-256: `b88c9444017b160ff61e8e82efefa27dc56a6b34ae142ab82a75f7246a95fd98`.
- Task 9 checked the recorded source manifest and every retained Release bundle file against Task 8; no product source/test/configuration changed or rebuilt for that acceptance card. Its identity was recorded at `2026-09-29T16:08:20.527123+00:00`.
- Computer Use selected the full retained Release path. Screenshots were inspected in that session's tool trace; no standalone screenshot files were exported. The written observations below are the retained portable evidence.

Early observations overlapped Debug and Release copies with the same bundle identifier, so they do not establish exact window identity. Later native text/cancellation/Settings/persistence observations were repeated during a confirmed single-copy Release interval, PID `26304`. A process inventory after Command-Q contained no MenuPocket process; relaunch PID `27645` showed the same existing rows. Re-querying a quit app through Computer Use could restart it, so such reinspection was not treated as a failure to quit.

The early live snapshot was empty with two unfinished tasks from yesterday. Later reads showed two existing current-day tasks; the run did not seed/save those rows or establish their provenance/change timing. Persistence comparisons use the later single-copy snapshot. No byte-for-byte claim about the production database or historical preference/onboarding state is made.

## Imported interface results

| Check | Result | Observation and scope |
| --- | --- | --- |
| Explicit Release launch/relaunch | Pass | Actual Today window appeared from the retained app, including after verified process exit. |
| Empty/populated Today snapshots | Pass for observed snapshots | English date, `0/0`, No tasks yet, informational yesterday count; later two existing rows with UUIDs, unchecked controls, English Edit/Delete labels and `0/2`. No saved action was performed. |
| Command-N and native text editing | Pass | Composer focus; Command-A/C/X/V and Command-Z/Shift-Command-Z operated field text. Saved-task undo is not claimed. |
| Whitespace input and new-draft cancellation | Pass | Whitespace left Save disabled and rows/count unchanged. Escape removed the composer and returned focus to Add. Nonblank temporary drafts were cancelled without saving. |
| Edit cancellation | Pass | Existing text populated the edit field; competing actions disabled; Escape preserved row/text/count and restored Edit focus. Saved editing remains unverified. |
| Delete confirmation/cancellation | Pass | Inline confirmation initially focused Cancel; Escape preserved both rows and `0/2`. Confirm Delete was not pressed. |
| Settings routes/reuse and Command-W | Pass for visible behavior | Task-window action and Command-comma opened English Settings; repeated requests retained the displayed surface; Command-W returned to Tasks. Exact controller identity is hosted-test evidence. |
| Keyboard focus order | Pass for exercised controls | Tab moved from Add to Settings then the first task checkbox; cancellation restored usable focus. Exhaustive traversal and VoiceOver were not observed. |
| Dark appearance and native zoom | Pass for exercised snapshots | Tasks/Settings were legible; zoom enlarged and restored the window while retaining its main areas. Minimum-size/long-content/light checks remain open. |
| Command-Q process exit | Pass | Release PID `26304` exited and the following inventory had no MenuPocket process. Status-item removal is separately blocked. |
| Settings Quit process exit | Pass | Release PID `25091` disappeared after Settings Quit. Later tool reinspection could restart the target; those restarted processes were subsequently stopped. |
| Saved tasks across actual Quit/relaunch | Pass for observed rows | Release PID `27645` showed the same two UUIDs, text, order, unchecked completion values, `0/2`, and yesterday count after the single-copy exit. No production test rows were added. |
| Actual status item: primary click, icon/count, width, removal | Blocked | Computer Use was not approved to use SystemUIServer. No alternate OS-input route bypassed the denial. |
| Dock/Command-Tab and status/Dock reopen/restore | Blocked | Computer Use was not approved to use Dock. App-window observations do not prove these routes. |
| Sustained close-all/minimized interval and exact same-window restore | Not tested to required scope | Close/minimize requests were exercised, but accessibility reinspection did not establish the interval, visible progress, or exact native window identity. |
| Saved CRUD/live count changes, read retry and failed-write recovery | Blocked for safe fixture verification | The fixture compiled, but Computer Use was not approved to use Task9AcceptanceFixture. Production rows were not mutated to seed scenarios. |
| All-completed, long-list/text, minimum size, light appearance | Not tested | Prepared fixture scenarios could not be exercised through the authorized interface. |
| Genuine closed-window day transition/wake | Not tested | No genuine transition/qualifying wake observed; injected-notification results remain automated support. |
| VoiceOver/additional displays | Not tested | No session or additional hardware coverage recorded. |
| Genuine login startup | Not tested | Settings reported Open at Login unavailable/off. No stable installed/authorized login copy or real login was exercised; registration was not changed. |

## Fixture isolation and cleanup

The prepared fixture used unchanged production owners/views, a separate database under `build/desktop-task-management/task-009/fixture.sqlite`, separate defaults suite and bundle ID `local.menupocket.task009.acceptance`, and a fake unavailable login service. It was non-sandboxed, so it could not establish production sandbox identity or actual login behavior. The authorized fixture compiler retry succeeded, but interface access was denied before an accepted launch; no fixture process/database was left running/created. Build success is not interface acceptance.

Task 9 cancelled temporary drafts and confirmation, made no saved add/completion/edit/confirmed-delete, changed no login registration or system appearance, and performed no installation/publication. Retained Release processes were quit. The original Debug path was restored using its existing on-disk build, final PID `28039`, with both rows visible and no composer/confirmation. Restoring the former process's in-memory revision is not claimed.

## Remaining acceptance gate

1. Obtain approved Computer Use access to SystemUIServer, Dock and the isolated fixture, or retain exact human observations for their required interactions. Do not bypass denied access.
2. Against one identified final Release process, observe actual status rendering/count changes/click/removal, Dock/Command-Tab, same-window reopening, and sustained closed/minimized intervals.
3. With isolated data, observe saved add/complete/uncomplete/edit/delete, failure/retry/draft recovery, all-completed/long-content/minimum-size states, and light appearance.
4. Observe genuine day/wake and login behavior when the environment permits, and record the available VoiceOver/display coverage. Keep unavailable checks explicit.

Full feature acceptance requires material interface requirements to pass on the final artifact. A product fix requires affected automated checks, rebuilding, replacement identity, and renewed affected interface observations. Documentation completion does not close Task 9 or the outstanding Task 1/6/7 system gaps.

## Local provenance

The imported narrative is `plan/desktop-task-management/evidence/task-009.md`. Local identity/process records and fixture preparation are under `build/desktop-task-management/task-009/`, including `identity.json`, `process-single-release.txt`, `process-after-release-quit.txt`, `process-relaunch.txt`, and `process-final.txt`. These directories remain Git-ignored; the results, identity, limits and pending gate above remain available in this tracked record.

The [historical Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) describes the superseded compact panel and retains its original limitations. It does not replace this desktop acceptance record.

## Focus outline follow-up — 2026-09-29

This is a separate Debug interface check of the Today-window focus fix, not a revision to Task 9's Release results or remaining gate. Source was `main` at `299edef1af01f12edd6a5f446f372f80aadadce8` with uncommitted focus and documentation changes. The checked app was `build/DerivedData/Build/Products/Debug/MenuPocket.app`, executable SHA-256 `20b4f983e31323d21f9194d0fc6cf63eba1d62c3cfa79b6855f3f8afef240596`, running as PID `37676` after its 14:36 EDT launch. Computer Use observed the dark Today window directly; screenshots were inspected in the tool trace but not exported.

After Add task and Cancel, Add showed the orange focus outline. Clicking empty header, task-list, and footer space each removed the outline; accessibility focus moved to the window. Tab then focused a task checkbox again. Add still opened its focused draft field, and Cancel removed it. A task-text click moved focus to the text. No task text was added, edited, or deleted.

T2 became completed during an earlier app relaunch in this verification session; the cause was not established. It was restored to the initial unchecked state through the checkbox, and the final window showed both rows unchecked with `0/2` progress and no open draft or confirmation. This focused Debug check does not verify Release, menu bar, Dock, light appearance, or the other open Task 9 acceptance items.

## Yesterday reminder highlight — 2026-09-29

Pass for the observed dark Today window: Computer Use confirmed `2 unfinished tasks from yesterday` renders in semibold red after rebuilding and relaunching the Debug app. The existing task UUID `1040897D-01D7-4ED3-ADAB-24CD1D8A788C`, text `1`, unchecked value, `0/1` progress, and yesterday count matched the pre-relaunch snapshot. No saved task action was performed. Screenshots were inspected in the tool trace; light appearance and Release were not checked for this follow-up.

Source was `fix/menu-bar-count-only` at `31333b3`, with the reminder styling and requirements changes plus pre-existing project/asset/design work. Xcode 27.0 (`27A266a`) built the shared `MenuPocket` Debug scheme successfully; the initial sandboxed attempt could not run Swift macro plugins, and the authorized build outside that sandbox passed. No new unit tests were added or run for this text-style change; `git diff --check` passed.

The app was `build/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`, executable SHA-256 `6984d75a3738d2ecbb4d0597f9a851355d2ea1da7f3971a7c3ed66d91799ee30`. A process check at approximately 16:01 EDT recorded PID `51096` at that exact executable path. The rebuilt app was left running. This focused check does not close the earlier full-feature acceptance gaps.

## Fixed task positions — 2026-09-29

Pass for the focused task-order interaction check. Computer Use exercised the unchanged production `DailyNotesState`, `TaskWindowController`, and `TaskWindowView` in a separate in-memory app, `build/fixed-task-order/TaskOrderFixture.app`, bundle ID `local.menupocket.taskorder.fixture`. It created Task 1, Task 2, and Task 3 in that visible order; completing Task 1 kept it first with muted text and `1/3`. Confirming deletion of Task 2 produced adjacent Task 1 and Task 3 rows with `1/2`. Editing Task 3 retained its second position; unchecking Task 1 retained its first position and showed `0/2`. Task 4 appended below both, and closing/reopening retained the same UUIDs and order. Screenshots and accessibility states were inspected in the tool trace. The in-memory fixture cannot establish saved-data persistence across process exit; the SQLite-backed regression covers that separately. The fixture was quit after verification.

The actual Debug app was then quit, confirmed absent from the running-app inventory, and relaunched from `build/DerivedData/Build/Products/Debug/MenuPocket.app`. Its existing A, B, and C tasks changed from the former C/B/A display to A/B/C, retaining all three UUIDs, unchecked values, `0/3`, and the yesterday count of 2. The window was visually inspected; no production task was added, completed, edited, or deleted. The rebuilt app was left running.

Source/artifact identity matches the [fixed-position regression record](DESKTOP_TASK_REGRESSION.md): `main` at `0c2833ec3d08426bfbc3b1dffb1cd41155c973eb` with the uncommitted ordering changes, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`, executable SHA-256 `d74b27d5d6d5d8197eb61b346be8b71798bb1cb5925ac071b86fe653e5164b63`. The running path/PID was confirmed at 17:02 EDT as PID `60085`. This Debug check does not establish Release, genuine login/day transitions, or the other earlier system acceptance gaps.

## Settings theme — 2026-09-30

This records the REQ-012 Theme choice. Source was `feat/settings-theme` at `29e13bde741d5283dbc06727de36ba30ef95cad2` (three commits on `main` `6d2f2bf`) plus these documentation updates. Xcode 27.0 (`27A266a`) built the shared `MenuPocket` Debug scheme.

Automated: the hosted suite passed 119 tests with 0 failures on that source, up from 113. New checks cover schema-1 preferences without a theme loading with every saved field and System, an unrecognized theme reading as System, a theme round trip through a fresh store and the reconciler, write protection blocking a theme change, the saved theme applied on manual and login launch, and live changes reaching both open windows until termination. `git diff --check` passed.

Rendered fixture: a temporary hosted test, not committed, opened the real Today and Settings windows with isolated defaults, three sample tasks in a fake repository, and a fake login service reporting enabled. The windows drew themselves to PNG for Dark, Light, and System; this Mac was in Dark. Both windows were legible in each theme, including the red yesterday reminder and focus outline. Settings showed Startup, then Appearance › Theme (System, Light, Dark), then App, with the existing rows unchanged. At the 500 × 380 pt minimum nothing was clipped. Screen Recording was not used, so these images show the app's own drawing rather than the screen, and the menu bar was not captured.

Saved preferences: before the first launch, the user's value was schema 1 without a theme key; it was backed up outside the repository. The new Debug build loaded it without rewriting it. The previously running Release copy was quit for this check with the user's approval.

Running app: `build/DerivedData/Build/Products/Debug/MenuPocket.app`, bundle ID `local.menupocket.app`, version `0.1.0` / build `1`, launched by `run.sh` from that source as PID `14192` at 12:36:04 EDT. Its code, `MenuPocket.debug.dylib`, has SHA-256 `49b10f3bd1c257a53c64e23d07bfbb941e6d037d0f013418655d6ce601c48e5d`. The later test action re-signed only the stub executable, now `9ceaae603d6902e7da6f0968d41b3a8bd9d2877ee7f2af87053a007e4c36877e`.

The user performed the hands-on checks below on PID `14192` and reported every one as passing. These are the user's observations; Claude did not see the screen.

| Check | Result | Notes |
| --- | --- | --- |
| Existing preferences show Theme set to System | Pass (user-reported) | |
| Light and Dark switch the Today and Settings windows immediately | Pass (user-reported) | |
| Menu bar count readable in each theme | Pass (user-reported) | |
| Theme kept after Quit and relaunch, without a flash | Pass reported; relaunch not corroborated | At 12:46 EDT PID `14192` was still the process launched at 12:36:04, so no relaunch appears in the process record. Persistence is covered by hosted tests and by the saved value below; the no-flash launch remains unobserved. |
| System follows a macOS appearance change | Pass (user-reported) | |

After the check, the saved value was `{"enabledModuleIDs":["demo.tasks","demo.status"],"menuBarDisplayMode":"iconAndInformation","moduleOrder":["demo.tasks","demo.status"],"schemaVersion":1,"theme":"system"}`: the first real save kept every earlier field and added only the theme. No task was added, completed, edited, or deleted. The Debug app was left running.

## Grouped Today checklist — Task 7, 2026-10-02

Pass, as reported by the user from direct manual observation of the isolated fixture: "Đã check và mọi thứ đúng như kịch bản. PASSED ALL". Claude did not observe or drive the interface; the user declined the Screen Recording grant needed for Computer Use. No screenshots were retained.

The fixture was `build/task-categories/task-007/GroupedChecklistFixture.app`, bundle ID `local.menupocket.task007.fixture`, executable SHA-256 `b5762422b917fc30d5fcf2cc3a1e5278f2fb539903faba81b049780b747f0bb9`. It is compiled from the unchanged production `DailyNotesState`, `TaskWindowController`, and `TaskWindowView` (`TaskWindowView.swift` SHA-256 `5d88e12e2b86b579fdd48666dee965cffbb0a035840d9d9e86099a8162b6982f`), with an in-memory repository and the defaults suite `local.menupocket.task007.fixture.categories`. Source/build identity matches the [Task 7 regression record](DESKTOP_TASK_REGRESSION.md#grouped-today-checklist--task-7-2026-10-01).

The user reported all 13 scripted checks as passing:

1. Group order, counts, and General last.
2. Mouse collapse and expand without changing counts.
3. Keyboard header toggling, with collapsed rows skipped by Tab.
4. Focus moving to the header when a group collapses around a focused row.
5. Focus returning to a collapsed header after a cancelled edit.
6. Completion and text edits keeping rows in place and other groups' disclosure states unchanged.
7. Deleting a group's last row removing that group, with focus on Add and headers disabled during confirmation.
8. Collapse state surviving close/reopen and fixture quit/relaunch.
9. Category removal moving tasks into General in creation order.
10. Empty, only-General, all-completed, and many-group layouts.
11. Unavailable state with Retry, then recovery.
12. Minimum-size layout with long names and text, in dark and light appearance.
13. The optional VoiceOver header announcement.

The user deleted the fixture's defaults suite after checking. The fixture is non-sandboxed and in-memory, so it does not establish production sandbox identity, SQLite persistence across relaunch, menu bar or Dock behavior, or Release behavior. It does not close the earlier acceptance gaps above. Final integrated category acceptance remains TASK-011.

## Category composer selector — Task 8, 2026-10-02

Pass, as reported by the user from direct manual observation of the isolated fixture: "ok mọi test đều pass". Claude did not observe or drive the interface; per the user's standing preference, no Computer Use or Screen Recording was used. No screenshots were retained, apart from the two the user shared during the first pass, described below.

The fixture was `build/task-categories/task-008/CategoryComposerFixture.app`, bundle ID `local.menupocket.task008.fixture`, executable SHA-256 `c902138fe87ab903ba819bae49df899d89e39cab2ea7aeb2d6e261ceca93f0da`. It is compiled from the production `MenuPocket/Notes` sources (`TaskWindowView.swift` SHA-256 `3c1c347acfc2ae2d274e594cc930fbb2f5fc0084142d2ae79992891d7bdfbcc1`), with an in-memory repository and the defaults suite `local.menupocket.task008.fixture.categories`. Source and build identity match the [Task 8 regression record](DESKTOP_TASK_REGRESSION.md#category-composer-selector--task-8-2026-10-02).

The first fixture build was defective: Command-X removed a category instead of cutting text, and the simulated write failure had no visible state. During that first pass, the user saw an edit save fail with "Could not save edit. Try again." while keeping its text and Fitness selection, because the simulated write failure was still on. A reseed then moved the edit into recovery with "Category: Fitness". Both are designed behavior. Only the fixture was rebuilt, with Option-Command fixture commands and a status title, and the user then reran every check on the rebuilt fixture.

The user reported all 16 scripted checks as passing:

1. A fresh draft starts in General; the picker lists saved categories in creation order, then General.
2. Return saves the text with the chosen category at the end of that group, updating group and daily counts.
3. The next new draft starts from the last-used category.
4. A pending draft keeps its text and selection through repeated Command-N and window close/reopen.
5. Escape discards the draft without changing the remembered category.
6. Choosing a menu item with the keyboard or dismissing the open menu with Escape never saves or cancels the draft.
7. Tab reaches the picker, Up/Down change it, Return there does not save, Escape cancels, and native text editing still works.
8. A failed add keeps text, selection, and the remembered category; a retry saves.
9. Reassigning a task into a collapsed group saves it, expands that group in original order, returns focus to the row's Edit button, and leaves the remembered category unchanged.
10. A text-only edit leaves other groups' collapse state unchanged.
11. Removing the selected category moves an active edit into recovery with its category name, and moves a new draft to General with a notice while keeping its text.
12. Renaming the selected category updates the picker label without changing the selection.
13. With no custom categories, only General is offered and saves; unavailable data disables the picker and Save until reads recover.
14. A pending draft keeps its text and selection across a day change and saves into the new day.
15. At the minimum size with a long category name, the picker truncates while Save and Cancel stay usable, in dark and light appearance.
16. After quit and relaunch, a new draft starts from the last saved category, and the unsaved draft is gone as designed. The VoiceOver label was optional.

The fixture is non-sandboxed and in-memory, so it does not establish production sandbox identity, SQLite persistence across relaunch, menu bar or Dock behavior, or Release behavior. It does not close the earlier acceptance gaps above. Final integrated category acceptance remains TASK-011.

## Category manager — Task 9, 2026-10-02

Pass, as reported by the user from direct manual observation of the isolated fixture: "ok tất cả test đều pass rồi". Claude did not observe or drive the interface; per the user's standing preference, no Computer Use or Screen Recording was used. No screenshots were retained, apart from the one the user shared during the first pass, described below.

The fixture was `build/task-categories/task-009/CategoryManagerFixture.app`, bundle ID `local.menupocket.task009.fixture`, executable SHA-256 `b4c97d2d586be393dd391bf567c50d7d7606a74e2dd92d132c154e34e4704d5d`. It is compiled from the production `MenuPocket/Notes` sources (`TaskCategoryManagerView.swift` SHA-256 `b4f8d4d6448c0c8fc7a6bbdd41fd77c578cc477a593cba0f8bb22e5101569698`), with an in-memory repository and the defaults suite `local.menupocket.task009.fixture.categories`. Source and build identity match the [Task 9 regression record](DESKTOP_TASK_REGRESSION.md#category-manager--task-9-2026-10-02).

During the first pass, removing Fitness in check 9 showed "Could not remove category. Try again." and kept the category; the user's screenshot also showed the renamed Classes category still saved. The fixture's simulated write failure from check 5 was still on. That message comes only from a failed repository write, and a headless replay of checks 4–9 through the production state and presentation (not retained) reproduced it with simulated failure on and removed both categories with it off, moving the pending draft to General with a notice. This is designed behavior: the failed removal kept the data and returned focus to the row's Remove… button. Nothing was rebuilt; the user turned the simulated failure off and reran the checks.

The user reported all 15 scripted checks as passing:

1. The sheet lists every saved custom category in creation order, including one without tasks today, then General with no actions; a long name wraps without hiding its buttons.
2. Creating a category adds it at the end, clears the field, adds no Today group, and makes it available in the composer's picker.
3. Reserved (`general`) and duplicate (`SCHOOL`) names show an inline error and stay in the field; nothing is created.
4. Renaming updates the Today group header without moving the group; other rows' actions are disabled during a rename; Escape in the rename field cancels only the rename.
5. With simulated write failure, create, rename, and remove show an error and change nothing; after turning it off, a retry succeeds.
6. The removal confirmation names the category and its count across all days, says tasks move to General and none are deleted, and starts with Cancel focused; Escape returns to the list with focus on that row's Remove… button and changes nothing.
7. Adding an older task while the confirmation is open makes Remove Category show the new count and ask again instead of removing; a second confirmation removes.
8. After removal, that category's tasks appear in General in their original order, overall progress is unchanged, and every day's tasks remain, now in General.
9. Removing the category a pending new-task draft selected keeps the draft text, moves the selection to General, and shows a notice.
10. While the sheet is open, Add Task and Command-N are unavailable and the window behind cannot be used; Manage categories… is disabled during a task edit or deletion confirmation.
11. Escape in the name field closes the sheet and returns focus to Manage categories…, a reopened sheet starts with an empty field, and closing the Today window during a removal confirmation leaves neither the sheet nor the confirmation on reopening while the task draft remains.
12. With simulated read failure, the sheet shows an unavailable state with Retry and cancels a pending removal; after reads recover, Retry restores the list.
13. Tab reaches Rename, Remove…, the name field, Create, and Done; Space and Return activate the focused button.
14. At the minimum window size, in dark and light appearance, the sheet fits and stays readable.
15. With no custom categories, the sheet shows "No custom categories yet." and General.

The fixture is non-sandboxed and in-memory, so it does not establish production sandbox identity, SQLite persistence across relaunch, menu bar or Dock behavior, or Release behavior. It does not close the earlier acceptance gaps above. Final integrated category acceptance remains TASK-011.

## Integrated category interface — Task 11, 2026-10-02

**In progress; actual-interface observations pending.** The user accepts Task 10 as complete and selected guided manual checks for Task 11. No Computer Use, screen recording, test rerun or rebuild was performed. The 49 source/configuration hashes still match Task 10 at the clean `feat/task-categories` revision `c7fcd71a69dc814f7a9383c701ab62c92eec01c1`.

The isolated SQLite fixture is `build/task-categories/task-010/CategoryRegressionFixture.app`, bundle ID `local.menupocket.task010.fixture`, executable SHA-256 `a5108843f39fecd9ca9828a2cfd93e88fa341396eb24fa3470ed691eda2d74a7`. Its signature verifies. Launch was confirmed at PID `88536` with `--scenario mixed`; its baseline is schema v2, five custom categories and 1/6 completed today. It uses the production views/state/delegate/controller/status item/Settings with separate SQLite/defaults and fake login/hotkey services. It is non-sandboxed. Process identity and prepared scenarios do not establish passing interface behavior.

The existing production Release is separately identified at `build/DerivedData/Build/Products/Release/MenuPocket.app`, PID `73790`, executable SHA-256 `1416d8db50a0dfcf171e1c2277371dc3bdb17bd5e48b6b49167b1ef2863eb20e`. Read-only immutable inspection found schema v1 and 15 saved tasks with no SQLite sidecars. Production database/defaults hashes, sizes and modification times match Task 10's preservation record at preflight. No live data was seeded or modified, no new v2 production build was launched, and no backup/restore or login-registration change was performed.

Manual checks cover saved category/task flows, failure/recovery, actual Quit/relaunch persistence, native routes, layouts/keyboard and separately labeled production/system observations. Manual outcomes and changed-data/preferences relaunch comparison remain pending; Task 11 is not complete. Raw preflight/baseline metadata is under ignored `build/task-categories/task-011/`; the local checklist/evidence is under ignored `plan/task-categories/evidence/task-011*.md`. VoiceOver, production upgrade, genuine day/wake/login and additional-display checks remain Not tested unless separately observed. Historical results above retain their original scope.

Baseline relaunch comparison: **Pass for untouched fixture SQLite data preservation across actual process exit/relaunch**. The user confirmed Command-Q; process inventory confirmed PID `88536` had exited, and the same fixture relaunched without reset at PID `92354`. The stopped/relaunched snapshots match for every saved category/task field, IDs, associations, day keys, completion, timestamps and rowid order; five categories, eight all-days tasks and 1/6 completed today remain. Production database/defaults preservation metadata still matches preflight. The fixture still matches its original seed and has no saved last-used category or collapsed group, so changed-data/preferences persistence, draft discard and visible relaunch behavior remain Not tested. No manual batch has been reported passing. Raw stopped/relaunched snapshots and `relaunch-comparison.json` are retained under the Task 11 build directory.

## Category removal repair (2026-10-02)

The agent directly operated the rebuilt native macOS fixture through Computer Use after the user requested the review findings be fixed. This supplements the earlier evidence; it does not mark all TASK-011 checks complete.

Fixture: `build/category-fix-20261002/CategoryFixFixture.app`, bundle ID `local.menupocket.fix20261002.fixture`, executable SHA-256 `6e5cddd4ed25d2b050341de8665948bd0fc0ba1782d2be05018d18d2838a13c7`. It compiles the current production views/state/controller/delegate/Settings/status item with the retained fixture harness, a separate SQLite file at `build/category-fix-20261002/fixture-data/mixed/notes.sqlite`, defaults suite `local.menupocket.fix20261002.categories.mixed`, and fake login/hotkey services. It is non-sandboxed. Its simulated date is October 2; the first category has the exact 775-character name from the defect reproduction and four assignments across three saved days. Source/build/artifact identities match the [repair regression record](DESKTOP_TASK_REGRESSION.md#category-removal-repair-2026-10-02).

| Observed check | Result |
| --- | --- |
| Fixed 480 × 360 sheet, long name and nonzero all-days count | **Pass:** the name scrolls; the four-task all-days notice and both buttons remain visible. Cancel starts focused. |
| Scroll name to the bottom | **Pass:** the complete name is reachable; the notice and footer remain in place. Native screenshots were inspected inline in the chat. |
| Escape cancellation | **Pass:** returns to the manager with the category intact and focus on its Remove action. |
| Simulated write failure | **Pass:** Remove shows an inline error and retains the complete saved category/task snapshot; a fresh confirmation is required. |
| Keyboard retry/confirmation | **Pass:** after writes recover, a new notice still reports four tasks; Tab reaches Remove Category and Return performs removal. |
| All-days removal preservation | **Pass:** exactly the target category disappears and its four assignments become General. All eight tasks retain UUID, rowid/order, text, day, timestamps and completion. |
| Result in Today | **Pass:** overall progress remains 1/6; General is 1/3 with Task 1, Task 5 and Task 6 in original relative order. |

Raw comparisons: `before-removal.json`, `after-failure.json`, `after-removal.json`, and `removal-comparison.json` under `build/category-fix-20261002/`. Failed-write snapshot equality and successful-removal field preservation both passed. The full suite and Release build were rerun after the source repair; earlier artifact observations are not promoted to this rebuilt fixture.

Full integrated category acceptance remains **partial**. Remaining unobserved flows/layouts/native routes, VoiceOver, production-identity menu bar/Dock behavior, first real-data upgrade/backup, and genuine day/wake/login/additional-display checks retain their previous Not tested/Blocked status. No live-data seeding, production launch, backup/restore, or real login/hotkey registration was performed. Current category guidance is synchronized, but the feature is not declared complete while material acceptance remains open.

## Soft Focus header and grouped list — Task 1, 2026-10-03

**Pass for Soft Focus TASK-001's native-fixture scope.** The final production view source and Debug build/test identities are recorded in [Task 1 regression](DESKTOP_TASK_REGRESSION.md#soft-focus-presentation--task-1-2026-10-03). This is an intermediate UI handoff; composer/menu changes, secondary-window polish, and final integrated acceptance remain later Soft Focus tasks.

Computer Use operated fresh `SoftFocusMixedFixture.app`, `SoftFocusEmptyFixture.app`, `SoftFocusManyFixture.app`, and `SoftFocusCompletedFixture.app` under `build/soft-focus-task-001/`. Bundle IDs are `local.menupocket.softfocus20261003.<scenario>.fixture`; their individual signed executable hashes are retained in `artifact-identity.json`. The completed fixture's SHA-256 is `4e95d29ba7d1820660bf73dca488021c68eb7ef6e915e0707d005e52450e9fe6`; the other signatures differ by bundle identity. They use the same compiled production views/state/controller/delegate/Settings/status item with separate SQLite files at `build/soft-focus-task-001/fixture-data/<scenario>/notes.sqlite`, defaults suites `local.menupocket.softfocus20261003.categories.<scenario>`, a simulated October 3 clock, and fake login/hotkey services. These fixtures are non-sandboxed, version `1.0`, build `1`. A process snapshot identified the final completed fixture at PID `72517` with its exact executable path; earlier scenario identity rests on the selected absolute paths, matching signed binaries, titles, and fixture task IDs. Screenshots were inspected inline; no saved screenshot files are claimed.

| Actual observation | Result |
| --- | --- |
| Mixed layout at 800 × 560 and 600 × 400 pt content sizes, Light and Dark | **Pass:** date/weekday, top actions, compact progress and distinct inset category surfaces are readable; the list scrolls. The initial matching-color issue was repaired and all four size/appearance combinations re-inspected on the rebuilt fixture. |
| Long name/text at minimum size, both appearances | **Pass:** a 179-character fixture category name wraps across three lines with its full count visible; task text wraps with checkbox and existing pencil/trash controls usable. |
| Collapse and keyboard traversal | **Pass:** MenuPocket's two rows disappear from the accessibility tree while its count stays 1/2 and daily progress stays 1/6. Tab from its focused collapsed header reaches Fitness directly. Space collapses Fitness and expands MenuPocket without changing counts. |
| Completion/uncompletion and rejected completion | **Pass:** Task 5 stays after Task 1; completion changes the group to 2/2 and overall progress to 2/6. A simulated failed uncompletion keeps the saved checkbox/count and shows the inline error. Retry after writes recover returns 1/2 and 1/6 without changing order. |
| Existing composer and top actions | **Pass for the observed routes:** Command-N focuses the bottom composer; its field, Category, Save and Cancel fit at minimum size. Escape cancels and focuses Add. The category icon opens the attached sheet; Escape returns focus to that header icon. The Settings icon opens the existing separate Settings window. |
| Empty versus unavailable, minimum size | **Pass:** a successful empty read shows 0/0 and No tasks yet; failed reads show an em dash, unavailable explanation and Retry, with Add/category controls disabled. Light/Dark unavailable views remain readable. Retry during continued failure stays unavailable; allowing reads and refreshing returns 0/0. |
| Many tasks | **Pass:** the 48-task/17-group fixture scrolls to Task 48, General and the yesterday reminder at minimum size in Dark; date/actions and 1/48 remain pinned above the list. |
| All completed | **Pass:** minimum-size Light view shows 6/6 with a full track; completed rows remain visible, muted and in saved order. |

The long category name was saved only through the disposable fixture's existing manager to establish the layout case; no user data was seeded or renamed. The mixed fixture's readonly SQLite inspection retains all six today task IDs and rowids/order. Native observations are narrower than full persistence/system acceptance. A Command-W/reselection attempt retained the draft, but Computer Use did not capture the closed-window state, so standalone close/reopen is **Not tested** here.

**Not tested in this task:** Settings Theme choices/System following, VoiceOver, full draft/deletion/recovery journeys, changed-data Quit/relaunch, production-identity system routes, Release, genuine login/day/wake, and additional displays. No production app/data launch or real login/hotkey registration change occurred. Existing category/system gaps remain open. All four operated fixtures were quit after the checks; raw source/build/identity/process/test records remain under the ignored Task 1 build directory.

## Soft Focus composer and row menu — Task 2, 2026-10-03

**Pass for TASK-002's focused native-fixture scope.** The final view/test source and 85/85 hosted tests are recorded in [Task 2 regression](DESKTOP_TASK_REGRESSION.md#soft-focus-composer-and-row-menu--task-2-2026-10-03). Settings/category-sheet styling remains TASK-003; final integrated Soft Focus acceptance remains TASK-004.

Computer Use operated `build/soft-focus-task-002/SoftFocusTask2Fixture.app`, bundle `local.menupocket.softfocus00220261003.mixed.fixture`, version `1.0`, build `1`. Final signed executable SHA-256: `429b5e9d8eebcffa491961750510068f1fc3494ce1c10e6a65c7277b6b234e4f`, built `2026-10-04T01:04:36Z` (October 3 locally). A process snapshot identified PID `14784` at the exact fixture executable path. The fixture compiles production views/state/controller/delegate/Settings/status item with fake login/hotkey services, a simulated October 3 clock, SQLite at `build/soft-focus-task-002/fixture-data/mixed/notes.sqlite`, and defaults suite `local.menupocket.softfocus00220261003.categories.mixed`. It is non-sandboxed and separate from production data/defaults. Screenshots were inspected inline; no saved screenshot files are claimed.

| Observation | Result |
| --- | --- |
| Composer/list geometry and long content | **Pass:** the field and Category/Save/Cancel sit below progress and above a scrolling list. At 600 × 400 pt in Light/Dark, long category selection truncates while both buttons remain visible; long task text wraps with checkbox and ellipsis usable. Default 800 × 560 pt was also inspected. |
| Native row menu | **Pass:** Tab reaches the always-visible trigger; Space/Return opens a menu containing only Edit and Delete…. Down/Return selects both actions. Mouse opening followed by keyboard selection works. Native tracking finishes before the composer/confirmation takes focus. Early candidates' focus/key-routing issues were repaired and these routes rechecked on the final binary. |
| Edit and action guards | **Pass:** Edit opens the top field with the selected task's text/category; Add, Categories, and other row menus are disabled. Escape returns focus to that task's menu. Final hosted tests cover rejected edits and native text commands; native failed-edit/retry behavior was also inspected during development. |
| Inline deletion | **Pass:** Cancel starts focused; Return on Cancel and Escape leave data intact. Tab/Return on Delete with writes rejected leaves the row/count and returns focus to its menu. A fresh confirmation after recovery deletes Task 3, changes 1/8 to 1/7, and focuses its surviving Work header. |
| Draft/category and error recovery | **Pass:** repeated Command-N and same-process Command-W/N retain pending text/category. With the category picker focused, Return does not save. Failed Add retains both values and shows its error; failed reads disable Add/Category/Save while keeping the field and reachable Retry. Recovery permits saving; Escape cancels only the pending draft. Native undo across close/reopen is established by the hosted field-editor test, not the Computer Use text-insertion path. |
| Labels | **Pass for accessibility-tree inspection:** task-specific menu labels, Edit/New task labels, Category, Save/Cancel, and inline confirmation actions are present. Spoken VoiceOver was not tested. |
| Actual quit/relaunch and saved data | **Pass:** process exit was checked before relaunching the same binary without reseeding. The visible count stayed 1/8; a fresh blank draft remembered the last saved category. All 10 saved tasks across three days and all five categories matched exactly before/after relaunch, including IDs, rowids/order, text, day, timestamps, completion, and assignments. |

Across the disposable Task 2 verification data, three tasks were added, Tasks 3 and 5 were explicitly deleted, and Task 1's text was edited. Compared with the retained nine-row baseline, all seven surviving original rows retained every other field and rowid; categories and schema v2 were unchanged. Raw identities/comparisons and exit checks are retained under ignored `build/soft-focus-task-002/`. The fixture was quit after verification.

These observations do not establish production-identity menu bar/Dock behavior, a real-data upgrade/backup, genuine login/day/wake, additional displays, spoken VoiceOver, Release behavior, remote CI, or the final combined UI. Existing category/system acceptance gaps remain open.

**User manual verification — 2026-10-04:** The user reported “ALL Passed!” after following the seven-step guide on the isolated Task 2 fixture. The guide covered Add and category Return without saving; repeated Command-N, draft close/reopen and native undo/redo; Edit Save/Cancel; keyboard menu activation; inline deletion Cancel and focus return; minimum-size Light/Dark usability; failed-save recovery; and saved changes after quit/relaunch. These results are user-reported. No additional agent checks were run, and no independent READY verdict is claimed; the remaining independent native review was skipped at the user's request.


## Soft Focus Settings and category sheet — Task 3, 2026-10-04

**Pass for the author-operated Task 3 native-fixture scope below.** Final production source hashes are recorded in [Task 3 regression](DESKTOP_TASK_REGRESSION.md#soft-focus-settings-and-category-sheet--task-3-2026-10-04). The author used production views/controllers/delegate/state in isolated, non-sandboxed fixtures with fake login/hotkey services and per-bundle SQLite/defaults. Settings observations began before the category focus-scroll correction, with identical Settings source; final category observations and preference-warning scenarios used the rebuilt final fixture. Author screenshots were inspected inline; no saved author screenshot files are claimed.

Fixtures under `build/soft-focus-task-003/`, version `1.0`, build `1`:

| Operated fixture | Bundle ID | Signed executable SHA-256 |
| --- | --- | --- |
| `SoftFocusTask3Fixture.app` | `local.menupocket.softfocus00320261004.softfocustask3fixture.fixture` | `cb03947e077bba7f8d38c277949969b2866b731d56fa65b2b4a9d1f297c0f52c` |
| `SoftFocusTask3ProtectedFixture.app` | `local.menupocket.softfocus00320261004.softfocustask3protectedfixture.fixture` | `246c4253fab65c64e7cc3337585f0194e06fd3d25b2befc1102771832960bd6b` |
| `SoftFocusTask3CorruptFixture.app` | `local.menupocket.softfocus00320261004.softfocustask3corruptfixture.fixture` | `cc3f2c6e065e7cb1bcae8ab60e0bbe9d8db8d14328e1860b6858003505a7d487` |

Each was selected by its exact absolute app path. Data lives in `build/soft-focus-task-003/fixture-data/<app-name>/<scenario>/notes.sqlite`; defaults use `local.menupocket.softfocus00320261004.categories.<bundle-id>.<scenario>`. The simulated clock remains October 3. The fixtures never initialize the production database or real login/hotkey services. The initially operated mixed fixture was identified at PID 36889 before its later rebuild; the final variants were selected by exact app paths with the signed identities above.

| Actual observation | Result |
| --- | --- |
| Settings layout and scrolling | **Pass:** default 560 × 440 pt content and minimum 500 × 380 pt window frame were inspected. Light/Dark/System choices worked; sections, status, and app/version information remained reachable by scrolling, while Quit stayed visible. Command-W/Command-comma closed/reopened Settings with the selected theme. |
| Settings errors and approval | **Pass:** fake login approval showed the disabled switch and approval action; the action called only the fake service. Failed login registration retained Off and showed the complete error. A fake shortcut conflict retained On and showed retry guidance. A failed preference save kept the previously selected theme and showed its inline error; retry after allowing saves applied Dark. |
| Preference warnings | **Pass:** the isolated newer-schema warning wrapped at minimum size with Theme/Quick Add disabled and App/Quit reachable. The corrupt-preference warning wrapped in System/Dark and Light; Theme remained editable and an allowed change applied while the session warning remained. Clicking the pinned Quit action exited each warning fixture. |
| Category layout and General | **Pass:** the 480 × 360 pt attached sheet was inspected over the minimum 600 × 400 pt Today content in Light and Dark. List/name content scrolled; Create/Done remained visible. General had its explanation and no Rename/Remove actions. Unused custom categories remained listed. |
| Create/rename/validation | **Pass:** Return created Reading and cleared its field. Reserved ` general ` and duplicate `READING` retained text with inline errors. Escape cancelled a rename without dismissing the sheet, returning focus to Rename; Space reopened rename, and Return saved Books with the same category ID. |
| Confirmation and long names | **Pass:** a trimmed 839-character fixture category name scrolled independently, with full all-days scope/count and Cancel/Remove visible in both appearances. The saved name length was verified by a read-only SQLite query. A historical-task insertion changed 4 to 5; confirmation updated the count and required confirmation again, with Cancel focused. Escape left the category and assignments intact. |
| Removal failure/retry/focus | **Pass:** rejected removal of Books retained the category, showed its command error, and required fresh confirmation. The final view scrolled its restored Remove focus into sight. Recovery plus a fresh confirmation removed Books and focused the new-name field. |
| Sheet guards and draft return | **Pass:** Command-N did not act behind the sheet. Done/Escape returned focus to Categories and kept the pending task draft. With failed reads, the sheet exposed reachable keyboard Retry; dismissal restored Today Retry focus and preserved draft text/category. |

All author-operated fixtures were quit after verification; the read-only exit check at `build/soft-focus-task-003/author-fixture-exit-check.json` found none running at 2026-10-04 16:44:28 UTC.

The final focus correction addresses a visible issue observed during this task: after a failed removal, focus could return to a row outside the rebuilt list's viewport. It adds scrolling for the existing stable row focus without changing category commands.

Independent reviewer `/root/review_task3` separately passed normal/minimum Settings in System/Dark and Light, Settings errors/recovery/reopening, category validation/CRUD/cancellation, visible restored removal focus, long-name/count-changed confirmation, unavailable/draft return, and native undo/redo after reopening. Its normal fixture was `build/soft-focus-task-003/review/SoftFocusTask3Review.app`, bundle ID `local.menupocket.softfocus003.review20261004`, executable SHA-256 `a03e4c6075f4e1938d82f363e6010997e3109d2c0314bf7f375f2a35a36a17e3`; source/artifact identities, screenshots and accessibility captures are retained in `review/`. After stalled computer-use selection calls and a supported session reset, it observed the author's exact protected fixture above with the full warning, disabled Theme/Quick Add and Quit available. Additional checking was stopped after the user's time/usage feedback. The independent corrupt-warning check and final READY verdict were not completed; that warning's pass remains author-operated evidence.

These are isolated native-fixture observations, not production/system acceptance. Spoken VoiceOver, genuine login/hotkey registration, production-data upgrade/backup, additional displays, Release, remote CI, and final combined Soft Focus acceptance are **Not tested** here. The prepared empty-category variant was not operated by the author. Existing category/system gaps remain open; TASK-004 owns the final integrated UI verification.

## Soft Focus integrated UI — Task 4, 2026-10-04

**Pass for the final integrated Soft Focus UI in isolated native fixtures.** Source was clean `main` at `962c47e4ca6b24b0bf0dc9f3fa3fc86ad34a8678`; no production fix was needed. The [Task 4 regression record](DESKTOP_TASK_REGRESSION.md#soft-focus-integrated-ui--task-4-2026-10-04) identifies the 123/123 focused tests, Debug build, and source manifest. The three UI source hashes match Tasks 2/3's recorded final inputs.

Computer Use selected the exact app paths under `build/soft-focus-task-004/`. Each version `1.0`, build `1` fixture uses production views/state/controllers/delegate, a simulated October 3 clock, an isolated SQLite file/defaults suite, and fake login/hotkey services without a sandbox. The unchanged harness SHA-256 is `7a2ca34005aef53b3757899018c38f1746d161f721becc5f678b534e4d1cc01b`. Screenshots were inspected inline; no saved screenshot files are claimed.

| Operated app | Bundle ID | Signed executable SHA-256 |
| --- | --- | --- |
| `SoftFocusTask4Fixture.app` | `local.menupocket.softfocus00420261004.mixed.fixture` | `f8801b8257cb611c2e4ca35b3d434e4dabd95caeda26359d2c3b81617f5a2ae1` |
| `SoftFocusTask4EmptyFixture.app` | `local.menupocket.softfocus00420261004.empty.fixture` | `b5bc9632ff088b5f9eb04b9280b90d6b1ddc94bb00901d0c6ed29e4c8d27c676` |
| `SoftFocusTask4ManyFixture.app` | `local.menupocket.softfocus00420261004.many.fixture` | `dd2803bb9456897ed8fead162d812eb93f1fb0eae29a895d73192d6c7eb10d8e` |
| `SoftFocusTask4CompletedFixture.app` | `local.menupocket.softfocus00420261004.completed.fixture` | `cb262ec555b449999385b9adb1044028c52b7720cdb4db81625c733814cc7bdc` |

Data paths are `build/soft-focus-task-004/fixture-data/<app-name>/<scenario>/notes.sqlite`. Reused harness defaults are `local.menupocket.softfocus00320261004.categories.<bundle-id>.<scenario>`; the Task 4 bundle IDs keep them separate from Task 3 and production. The mixed process was identified at the exact executable path as PID `86115`, then PID `94530` after relaunch. Artifact creation was recorded at 2026-10-04 17:31:10 UTC.

| Final native check | Observed result |
| --- | --- |
| Geometry and appearance | **Pass:** mixed Today at default 800 × 560 and minimum 600 × 400 content sizes, plus native zoomed wide layout; Light/Dark and the System theme choice were observed across Today/Settings. The centered column, header, composer/actions and long text remained usable. This was a focused matrix, not every scenario at every size/theme combination. |
| Empty, many, completed and collapsed | **Pass:** empty showed `0/0` and its distinct message; its sheet showed no custom categories and read-only General. The 48-task fixture scrolled to Task 48, General and yesterday's reminder at minimum Dark size. Completed rows remained muted and checked at `6/6`; click uncompletion changed it to `5/6`, then Tab traversal and Space restored `6/6` without moving the row. Collapse removed row controls from the accessibility tree while retaining counts. |
| Composer and task actions | **Pass:** repeated Command-N and same-process Command-W/N retained a pending draft. Return after Tab to the category picker did not save. A rejected Add retained text/General and `1/6`; read failure showed unavailable progress, disabled Add/Category/Save and reachable Retry. Recovery saved the task and showed `1/7`. Keyboard menu selection opened Edit; saving returned focus to the same row menu, Space reopened it, and Delete… showed inline confirmation with Cancel focused. Escape cancelled without deletion. Native undo/redo is established by this run's hosted test; confirmed task deletion was not repeated in this native pass. |
| Category integration | **Pass:** the sheet opened over a new-task draft and blocked Command-N. Reserved General validation retained text. Create and rename preserved the new category's ID. Rejected removal returned to a visible focused Remove action with its error; recovery required fresh confirmation, and Tab/Space removed the disposable unused category. An 839-character name scrolled independently in Light/Dark while the all-days count and Cancel/Remove remained visible. Escape cancelled removal/dismissed the sheet; the underlying draft survived this and the Settings journey. |
| Settings integration | **Pass:** minimum 500 × 380 window size, scrolling sections and pinned Quit, repeated Command-comma close/reopen, and System/Light/Dark choices. Rejected preference saving kept Light with a visible error; recovery applied Dark. Fake approval-required status and shortcut conflict messages remained readable, with app information reachable below them. No real service registration changed. |
| Changed saved data after relaunch | **Pass:** actual task Add/Edit, category changes and collapse were made before Quit. Process exit was confirmed, then the same mixed artifact reopened without reset/reseeding. All nine all-days saved rows (seven today), category rows, schema v2 and isolated defaults matched exactly; visible `1/7`, the added task and collapsed group returned. Raw snapshots/comparison are retained under the Task 4 directory. |

All four Task 4 fixtures were quit; `final-exit-check.json` found none running at 2026-10-04 17:47:01 UTC. No user-facing blocker was observed in this UI scope. Task 4 is complete for focused automated/native-fixture acceptance, with no independent READY verdict claimed. Production-identity menu bar/Dock behavior, real-data upgrade/backup, genuine login/day/wake/hotkey registration, additional displays, spoken VoiceOver, Release and remote CI remain **Not tested here**; prior category/system acceptance gaps retain their original status.

## Mouse and keyboard focus visibility — 2026-10-04

**Pass for the tested pointer/keyboard transitions.** Computer Use operated production views/controllers in `build/keyboard-focus/KeyboardFocusFixture.app`, bundle `local.menupocket.keyboardfocus20261004.fixture`, with a separate SQLite database/defaults suite and fake login/hotkey services. Initial fixture executable SHA-256: `e8643784d647f9c0d0559b5b3ff7e63cc78a0069a609444e53e306292c1480e2`. The harness was then rebuilt only to reassert the legacy/demo host window sizes; final SHA-256: `90519c6b53d5c914c7689226138fcac112f8aba3e8316171044b3f5670e81d8b`. Production UI source stayed unchanged between these artifacts. Screenshots were inspected inline; no saved screenshot files are claimed. Actual pointer checks used screenshot coordinates, since accessibility button activation does not establish a mouse-input transition.

- Today/category manager in Dark: mouse-opened group/menu/confirmation had no non-text focus outline; Tab showed the unchanged accent outline on buttons, checkboxes, and the category picker. Clicking a focused checkbox hid its outline while updating completion. Tab/Shift-Tab followed by Space on confirmation Cancel restored visible focus to Remove; mouse Cancel/Done restored logical focus without an outline. Mouse Edit retained native text-field focus.
- Settings in Light: theme and both switches responded to mouse clicks without a focus ring, using only fixture preferences and fake registration services. Native Settings/demo keyboard traversal follows the existing macOS Keyboard navigation setting; traversal was not enabled or demonstrated here.
- Quick Add: the fixture command opened the production capture panel; clicking and typing still worked, and Escape discarded the capture. This does not claim real global-hotkey acceptance.
- Retained panels in Light: Tab showed a legacy notes menu outline; a physical checkbox click hid it and updated the isolated completion count. Demo Refresh responded without a pointer focus outline.

The fixture was quit after verification. The exact checkout Debug app at `build/DerivedData/Build/Products/Debug/MenuPocket.app` was restarted after inspecting Today for an open draft. It retained the same task/category IDs and `0/1` count; Tab visibly focused Manage categories, and a mouse click on noninteractive header space cleared the outline. No production task or preference edit was made during this check. Its executable hash is recorded in the regression section and the source/artifact manifest.


## Inline task editing — 2026-10-04

**Pass for the tested inline-edit native fixture scope.** The author operated the current production views/state/delegate through Computer Use in `build/inline-edit/InlineEditFixture.app`, bundle `local.menupocket.inlineedit20261004.fixture`. It uses a separate SQLite database/defaults suite, 100 saved Today tasks, a simulated October 3 clock, and fake login/hotkey services. Final v4 executable SHA-256: `f60913f519dc25dabb9be7044b4bf8c2ee963b6a74030ecdafd753e70a7cad61`. Screenshots were inspected inline; no saved screenshot files are claimed.

| Native check | Observed result |
| --- | --- |
| Edit at the bottom with a pending Add | At minimum 600 × 400 in Light, editing Task 65 in General replaced that row with the selected text field, category, Save and Cancel. All controls were visible without manual scrolling after entry. Add was hidden and its draft retained. The active group could not collapse. |
| Category reassignment and Return Save | Selecting Category 1 kept the editor in General until Save. Return persisted `Inline v4 category move`, moved the task into Category 1, and visibly centered it between Task 49 and Task 81. AX focus returned to `taskActions-00000000-0000-0000-0000-000000000065`. `Pending Add v4` reappeared unchanged without stealing focus. |
| Save failure and Escape | Simulated write failure retained `Rejected v4 draft` in the inline editor with `Could not save edit. Try again.` directly below its controls. The whole editor/error remained visible at minimum size in Dark. Escape restored the saved task, removed the error, visibly centered the row, and returned focus to its actions; the separate Add draft was preserved. |
| Saved destination near the start of a group | Saving Task 17 as `Inline v4 second row` in Dark at minimum size visibly centered it between Task 1 and Task 33, with focus on its actions and Add unchanged. This specifically rechecked the earlier offscreen destination defect. |
| Pointer input and cancellation | Earlier v3 checks confirmed clicking and typing in the inline field, then clicking blank space, retained the unsaved text without saving. Mouse Cancel restored the original task and pending Add with row-action focus. V4 changed only scroll anchors and rechecked Escape cancellation above. |

Earlier artifacts additionally exercised native undo/redo during focused typing, category changes without Save, a successful retry after simulated failure, and same-process window close/reopen retaining the edit/error. Those observations support unchanged editor/state behavior; they are not final-v4 independent UI acceptance. Read-only final SQLite inspection retains task UUIDs and rowids 17/65, their unchanged completion status, and 100 Today tasks after the saves. The hosted native Return/failure/Escape test and existing state contracts passed in the final [91-test regression](DESKTOP_TASK_REGRESSION.md#inline-task-editing--2026-10-04).

The independent reviewer examined the final source, test results and author-operated native records separately; its own Computer Use acquisition stalled, so an independently operated final native pass is not claimed. The production app and saved user data were not replaced or edited. Full-suite, Release, remote CI, spoken VoiceOver and genuine system-service acceptance were not run for this change. Task-owned app cleanup is recorded in `build/inline-edit/cleanup.json`; sources, databases and evidence remain.

## 2026-10-06 — Retained History navigation shell (TASK-008)

Scoped native fixture, not full History/calendar feature acceptance. Source base `f37eadffa0021c94007a6b7d758897178e3d18cf` plus TaskBrowserView/controller/Today state and command changes. Harness compiles the current production views/state/delegate using Swift 6, Debug, macOS 14 target, separate SQLite/defaults and fake login/hotkey services. Fixed Toronto October 6 clock; 70 Today tasks and one unfinished yesterday task. Bundle `local.menupocket.task008.fixture`, unsandboxed fixture arrangement. Executable SHA-256 `3b81ed31b819567860de8f2fb7fa8b9df3bc45e59bdb877ad76d93437db39131`; harness SHA-256 `d5caf0ddeac596768c6451c47d7a1c955e54d1a784a8928cac94cc22d25d9347`. Exact paths, source hashes, build arguments, screenshots and harness remain under ignored `build/task-history-task008/`; runnable bundles were removed after verification. The native snapshot predates only restoration of the yesterday reminder's original red styling; the final Debug build includes it.

| Journey | Result and evidence |
| --- | --- |
| Calendar → History → nested Unfinished → Back chain | Pass: same visible task window, headings and back controls, no exposed hidden Today controls in AX tree. `unfinished-final.png`, `history-minimum-final.png`. These are placeholders. |
| Pending draft/composer and long-list offset | Pass: `Final retained draft` remained visible after the chain; Task 19 remained the first visible row and AX scrollbar stayed exactly `0.2756831018165166`. `today-before-final.png`, `today-after-final.png`. |
| Keyboard entry/back focus | Pass: Return on Back to History/Today; focus returned to the calendar entry, Space reopened History. Initial group-focus fallback was repaired and rechecked. |
| Native Command-N/W/comma/Q | Pass: Command-N from History returned to Today and its text field; Command-W then Command-N reused the window and draft; Command-comma opened retained Settings; Command-Q stopped the fixture. |
| Default and minimum layout, appearances | Pass: 800 × 560 and 600 × 400 content sizes observed; Today and History controls remained usable in Dark/System and Light. `today-minimum-final.png`, `history-minimum-final.png`, `history-light-minimum-final.png`. |
| Saved rows/schema during browsing | Pass for the recorded scoped journey: all tables/rowids/order/fields/schema compare equal in `preservation-before.json` and `preservation-after.json`. Theme/onboarding changes were confined to the fixture suite. |
| Native menu-bar/Dock clicks, missing-anchor removal, manager/edit/delete guard UI, VoiceOver, real day/wake/time-zone changes | Not tested here. Route/guard/fallback/termination/quiet-login paths have focused hosted evidence; this does not establish genuine system or accessibility acceptance. |

The initial fixture crashed because the harness chose its bundle identifier as a defaults suite; a distinct suite fixed startup. It did not indicate a production app crash. Subsequent native checks used the repaired identified artifact. Final-feature layouts and integrated production-identity acceptance remain subsequent work.

## 2026-10-06 — History date list and day detail (TASK-009)

Scoped native fixture, not full History/calendar feature acceptance. Source: uncommitted working tree on base `4c4c81f03716894322bb2948d4c57525c487b1d6`, including newest-first list order and the Select a day heading. Harness `build/task-history-task009/FixtureMain.swift` compiles the current production views/state/delegate (Swift 6, Debug, macOS 14 target) with separate SQLite/defaults, fake login/hotkey services, and a fixed Toronto clock (Tuesday, October 6, 2026). Bundle `local.menupocket.task009.fixture`; first run executable SHA-256 `82c5f9d9efc4c630a0cafa6181b524c00f56aa5ddeb693f0f3e65d7da0507371`, fix recheck `14d4b83f1462b8ba78fb715d9e521b112891d72497d6c3873d4b67494475f2c8` (committed source). Driven by Claude through Computer Use background app control with the user's permission; steps follow ignored `build/task-history-task009/TEST-PLAN.md`.

| Journey | Result |
| --- | --- |
| Calendar entry → History in the same window, heading, Back to Today, Unfinished entry, month header | Pass |
| Date list newest first with counts (Oct 20 0/1, Oct 6 0/2, Oct 5 3/5 selected, Oct 3 2/2, Oct 1 0/3); detail beside list at 800 pt | Pass |
| Read-only detail: date, 3/5, groups Work 1/2 / long category 1/1 / General 1/2 in creation order, status icons, no checkboxes/actions; long task and category text wrap | Pass |
| Unfinished/Completed filters keep 3/5 and group counts; switching day keeps filter; "No completed/unfinished tasks for this day." | Pass |
| Saved future day (Oct 20) readable; empty day (Sep 5) 0/0 "No saved tasks for this day."; 100/125 day with 125 rows | Pass |
| Previous/Next across Dec 2025 ↔ Jan 2026; This month selects Oct 6 with All; future November shows "No saved tasks this month." and Select a day | Pass |
| History disclosure does not change Today groups; yesterday reminder opens Oct 5 with Unfinished | Pass |
| Narrow stacked layout (list above detail, scrollable) | Pass at ≈504 × 276 content. The test tool's resize bypassed the 600 × 400 minimum, so the real-drag minimum was not observed. |
| Keyboard: Tab to month controls, This month, day rows, filter (one Tab stop with Keyboard navigation off); Space/Return activate; Right arrow moves one filter option | Pass. Initial finding: the scroll view did not follow keyboard focus. Fixed; recheck Pass — tabbing to the General header below the fold scrolled it into view. |
| Light (fixture Theme setting) and Dark | Pass for readability. Initial finding: Light cards blended into the plain background. Fixed with Today's tinted canvas; recheck Pass. |
| Draft "Draft kept through History" survives History visit; Back focuses the calendar entry | Pass |
| Group disclosure per day | Initial observation: collapsing General on Oct 20 also collapsed it on Oct 5. Fixed: choosing another day starts expanded; refresh of the same day keeps it. Recheck Pass. |
| Edit/delete/manager guard UI, VoiceOver, macOS Keyboard navigation on, real-drag minimum size | Not tested here. Guards have focused hosted evidence from TASK-008. |

The fixture was quit; it and the Debug test host were unregistered from LaunchServices and moved to Trash, and the Trash paths were unregistered. No production data/defaults/login/hotkey state was touched.

## 2026-10-06 — History month calendar (TASK-012)

Scoped native fixture, not full feature acceptance (TASK-014). Source: uncommitted working tree on base `c8d1fae`. Harness `build/task-history-task012/FixtureMain.swift` (TASK-009 harness and sample data; separate SQLite/defaults, fake login/hotkey, fixed Toronto clock Tuesday, October 6, 2026), compiled with all production sources except `MenuPocketApp.swift`. Bundle `local.menupocket.task012.fixture`; first build executable SHA-256 `2894be55…dcae`, fixed recheck `8aae167e5c005e60b0e13323d3b95bdf3d7449416c6d679b8397b816bde5c2c3`. Driven by Claude through Computer Use background app control with the user's permission (fixture bundle only), Dark appearance.

| Journey | Result |
| --- | --- |
| Calendar entry → History; Sun–Sat header; October 2026 starts Thursday; cells 1 0/3, 2 0/0, 3 2/2, 4 0/0, 5 3/5, 6 0/2, saved future 20 0/1, other future days —; Today = filled circle on 6; selection = outline on 5; detail beside grid at 800 pt | Pass after fix. Initial finding: blank padding cells grew vertically and pushed the weeks below the fold. Fixed by excluding padding from grid sizing; recheck Pass. |
| Click Oct 3 with Unfinished filter → filter kept, 2/2, "No unfinished tasks for this day."; saved future Oct 20 opens read-only detail; empty future Oct 21 click does nothing | Pass |
| This month selects Oct 6 with All | Pass |
| Keyboard: Tab reaches Previous/Next/This month then calendar cells; Down/Right move by week/day; Return on empty future does nothing; Up past the 1st moves to September with focus on Sep 25; Space selects Sep 30 (1/2, Work 1/1, Home 0/1) | Pass. Crossing months applies the existing month-change selection clamp (selection moved to Sep 6 before Space). |
| August 2026 starts Saturday; Aug 12 shows 100/125 in full; January 2026 starts Thursday with Jan 1 1/1; December 2025 starts Monday with Dec 31 1/2 | Pass |
| Accessibility label of the Today cell exactly "Today, Tuesday, October 6, 2026, 0 of 2 complete"; empty future cells are not exposed as buttons | Pass (tool withholds other titles) |
| Narrow stacked layout: calendar above detail, scrollable to detail | Pass at ≈502 × 302; the tool's resize bypassed the 600 × 400 minimum, so the real-drag minimum was not observed |
| Unavailable month + Retry, Light appearance, VoiceOver, macOS Keyboard navigation setting on | Not tested natively. Unavailable cell state has hosted model coverage (TASK-011). |

The fixture and Debug hosts were quit, unregistered from LaunchServices, and moved to Trash; Trash paths were unregistered. No production data/defaults/login/hotkey state was touched.

## 2026-10-06 — Final History feature native acceptance (TASK-014)

Final-feature native fixture for History, Unfinished, and the month calendar. Source: committed HEAD `4a8b679f0de7aec5d7a827f6640eef002e7fa1e6`, clean worktree. Harness `build/task-history-task014/FixtureMain.swift` (SHA-256 `a51ce5a7…8263`) extends the TASK-012 sample data with 30 Today tasks and 40 unfinished June/July days. It wraps the production SQLite repository so History month, day, and Unfinished-page reads throw only while a flag file exists (injected failures, not real storage faults). Separate SQLite/defaults suite `local.menupocket.task014.fixture.defaults`, fake login/hotkey, fixed Toronto clock Tuesday, October 6, 2026. Swift 6.4, Debug (`-Onone`), macOS 14 target, all production sources except `MenuPocketApp.swift`. Bundle `local.menupocket.task014.fixture`; executable SHA-256 `aa6c4dc92e5d9995fc29eb10b53de970a5b958318a9138267988d4935fc63d5b`. Claude drove the fixture through Computer Use background control, with the user's permission and access limited to the fixture bundle. The user ran the system-input checks themselves and reported Pass.

| Journey | Result |
| --- | --- |
| Calendar icon → History in the same window (one window ID throughout), heading, Back to Today; Today cell 0/30 matches Today progress | Pass (Claude) |
| History → Unfinished → day → Back to Unfinished → Back to History → Go to Today; read-only day detail with the Unfinished filter; History shows the selected Unfinished day | Pass (Claude) |
| Focus return: the selected Unfinished row (scrolled into view, Dec 31, 2025 after Load more), the Unfinished entry, the calendar icon, and the yesterday entry; Space activates each | Pass (Claude) |
| Unfinished index: newest first, past days only (no Oct 6/Oct 20), first page 31 days ending Jun 23, Load more reaches Dec 31, 2025 with no duplicate and no further Load more; Back to Unfinished keeps appended pages | Pass (Claude) |
| Injected failures: Load more failure keeps loaded rows and shows "Could not load more days" + Retry; month failure shows message + Retry with Unavailable cells (no zeros); day failure shows its own message + Retry; each Retry recovers only its pane | Pass (Claude) |
| Draft "Draft kept through TASK-014", open composer, and Today scroll offset survive every History/Unfinished round trip, Close/Show Tasks, and Minimize/Show Tasks | Pass (Claude) |
| Yesterday entry → Oct 5 with Unfinished filter (2 tasks); Back to Today restores the bottom offset | Pass (Claude) |
| Today completion → History Oct 6 cell and detail both 1/30, Home 1/10 | Pass (Claude) |
| File > Add Task from History → Today with the draft field focused; Close/Minimize then Show Tasks → Today in the same window; Settings from History and the app menu reuse one window | Pass (Claude) |
| Category manager sheet open → calendar icon dimmed and unreachable | Pass (Claude) |
| Light theme on History and Unfinished; Dark on all screens | Pass (Claude) |
| Quit (process exit confirmed) and relaunch without reseeding: completed task, Light theme, and 800 × 560 window kept; unsaved draft cleared as designed | Pass (Claude) |
| Fixture menu bar item click and Dock icon click from History → Today in the same window | Pass (user-reported) |
| Real corner drag to minimum: stops at 600 × 400 content, History stacks and scrolls | Pass (user-reported). Claude's tool resize bypassed the minimum (102 × 102), as in TASK-009/012; this is not product evidence. |
| VoiceOver across calendar days and Unfinished rows | Pass (user-reported) |
| Saved data | Pass: schema, every row with rowid, and the defaults suite compared seed → before quit → stopped → after relaunch → final. Only the intentional Today completion and theme change differ. Browsing, injected failures, Retries, and the user's checks wrote nothing. |

Observation: one raw-input click on blank space in the Unfinished list left the window on History rather than opening a day. It did not reproduce with element presses or keyboard; the code has no route change on activation/refresh. Treated as a tool artifact, not a defect.

Not tested: genuine day change/wake/time-zone change (hosted coverage only), edit/delete guard UI (hosted coverage), macOS Keyboard navigation setting on, production-identity app. The fixture was quit, unregistered from LaunchServices, moved to Trash, and its Trash path unregistered. The user's `/Applications/MenuPocket.app` and its data were not touched; the user quit it themselves during the session. Evidence: ignored `build/task-history-task014/` (screenshots, preservation snapshots, artifact identity).

## 2026-10-07 — Menu bar glance native fixture acceptance (TASK-005/006)

Isolated native fixture for the read-only menu bar glance (docs REQ-016). Source: committed `b700eafca3f09c492dcdcf4e1ca75cadca7b3d80` (TASK-004), clean worktree; `ad3bc47` (TASK-005) changes documentation only. Harness `build/glance-task005/FixtureMain.swift` (SHA-256 `a5863adb3e2ce51271e67cbe81d345159b6328a29084e11e4176b2bc1f65606f`), compiled with every production source except `MenuPocketApp.swift`: Swift 6.4 (Xcode 27.0, `27A266a`), Debug (`-Onone`), macOS 14 arm64 target, ad-hoc signed. Bundle `local.menupocket.glance005.fixture`; executable SHA-256 `b2dd430fb6a651b46137101d11880fc1e2faf6061a93654bfb5c50e854ac4fa2`. Five scenarios (`normal`, `few`, `empty`, `alldone`, `unavailable`), each with its own SQLite file and defaults suite `local.menupocket.glance005.fixture.<scenario>`, fake login and hotkey services, a fixed Toronto clock (Wednesday, October 7, 2026), and flag files that make the Today or Later read throw (injected failures, not real storage faults). With the user's permission, Claude drove checks 1–10, 13, 15, and 16 through Computer Use, limited to the fixture bundle, with macOS in Dark. The user then opened the `normal` glance themselves and reported "Everything's good so far" (2026-10-07, about 21:15 UTC) without itemizing further checks.

| Check | Result |
| --- | --- |
| 1. A primary click opens Today, from an idle Later tab, from History, and after right-click then Esc | Pass (Claude) |
| 2. Right-click shows the agreed layout: `Wed 7 Oct` and `3 of 11 done` on one line, a bar across the header, 5 rows, `3 more in Today`, `Later · 3 remaining`, 4 actions without shortcut glyphs | Pass (Claude); the user also saw the glance in `normal` |
| 3. Control-click shows the same glance | Pass with a synthetic Control-flagged left click (Claude). A physical Control-click is **Not tested**. |
| 4. The header is not highlighted on hover, is skipped by Up/Down, and does nothing when clicked | Pass (Claude) |
| 5. Rows follow the Today window's order; collapsed Home is listed; category text only with several groups (`few` shows none); a truncated title's tooltip shows the full multiline text and the full category name; no Later rows | Pass (Claude) |
| 6. `N more in Today` is readable when highlighted and opens Today | Pass (Claude) |
| 7. A row (from History), Open Today, Add Task… (idle Later → Today composer, Later draft kept), Settings…, and Quit work. Add Task… is disabled during a Today edit, a Later edit, a deletion confirmation, and Manage categories. Open Today during a Later edit stays on Later and keeps the edit. | Pass (Claude) |
| 8. After an add, a Move to Today, and a completion in the window, the next glance matches without relaunch | Pass (Claude) |
| 9. `empty`, `alldone`, and `unavailable` match REQ-016; Retry recovers (`1/2`); a Later-only failure hides only the Later line | Pass (Claude) |
| 10. Esc and click-away change nothing (pending deletion, drafts, tab) and raise no window; a minimized window stays minimized | Pass (Claude). Not tried with another app frontmost. |
| 11. Themes | **Fail of the planned assumption, accepted by the user.** With Theme = Light and macOS in Dark, the windows turn light, but the glance stays dark like the app's own File menu: menu bar menus follow the macOS appearance, not the Theme setting. The glance is legible in Dark. On 2026-10-07 the user decided to accept and document this native behavior, with no code change. macOS in Light is **Not tested**. |
| 12. VoiceOver: header as one item, the "Show quick look" custom action, item reading, and right-click → Esc → VO-Space opening Today | **Not tested.** Hosted tests cover the header's accessibility label and value, the custom action's registration, and press routing without a mouse event. |
| 13. Quit from the glance exits and removes the menu bar item | Pass (Claude) |
| 14. The status item tooltip ends with "Right-click for a quick look." | **Not tested** natively: a synthetic hover showed no tooltip. Hosted tests cover the text in both states. |
| 15. `Later · N remaining` has the right N in `normal`, `empty`, `alldone`, and `unavailable`, is absent in `few`, and drops after Move to Today | Pass (Claude) |
| 16. The Later line opens Later, also from History; with a Today edit open it brings the window forward without switching and keeps the edit | Pass (Claude) |
| Saved data | Pass. After the user's session, `few`, `empty`, `alldone`, and `unavailable` matched their post-TASK-005 snapshots, and `normal` matched its fresh seed, which was reset after Claude's run (11 Today tasks with 3 done; 3 unfinished Later tasks). Opening and browsing the glance wrote nothing. |

Not tested: VoiceOver (12), the native tooltip (14), Themes with macOS in Light (11), a physical Control-click (3), dismissal with another app frontmost, a production-identity app, and quiet login startup. The fixture was quit, unregistered from LaunchServices, moved to Trash with `FileManager.trashItem` (2026-10-07T21:16Z), and its Trash path unregistered. The user's `/Applications/MenuPocket.app` (executable SHA-256 `2f230e6c…82f9f`, unchanged) and its data were not touched. Evidence: ignored `build/glance-task005/` (`MANUAL_CHECKS.md`, `artifact-identity.txt`, scenario snapshots `final-*.txt` and `task006-*.txt`).

## Movement destinations — Task 6 initial native attempt (2026-10-07)

**Native acceptance: BLOCKED.** Isolated fixture used current production `TaskWindowController`/`TaskWindowView`, SQLite `/private/tmp/menupocket-task6-native/notes.sqlite`, defaults suite `local.menupocket.task6-presentation`, and injected October 7 Toronto clock. It did not initialize the production app delegate or login/hotkey services. Final executable SHA-256 `cd76a7fe70ac64de701f2cf5066135b5e7c5ffbf9e86555ab620dd6487615f86`; observed PID 22436 at the fixture's exact temporary executable path. Current interface was Dark, initial 800 × 560 pt content size; four tasks: Work (two), Home (one, collapsed), General (one), plus an empty custom category.

The first disposable fixture crashed in its own startup force unwrap because its defaults-suite name matched its bundle identity. A separate presentation-suite name corrected startup; the repaired fixture opened the production Today interface. This crash did not exercise Task 6 drop routing. Crash/build evidence is retained under ignored `build/task6/`.

Computer-use handle drag exposed the transient Empty category and group footer targets. The attempted Work-first → Work-second drop saved nothing; subsequent click/Escape did not clear transient presentation. The automation/native-loop versus implementation cause remains unresolved. This establishes only startup and temporary destination rendering. Actual successful row/header/empty/collapsed drops, insertion/highlight correctness and native cancellation are **Not tested/Blocked**, not passes. Callback tests are separate evidence in [Task 6 regression](DESKTOP_TASK_REGRESSION.md#movement-destinations--task-6-2026-10-07). Independent review remains BLOCKED on these gaps. Resolve native-session behavior before closing Task 6 acceptance; Task 7 edge scrolling/reveal and Task 8 keyboard actions remain separate work.

The fixture process was stopped by its exact path, its bundle unregistered and moved to Trash with `FileManager.trashItem`, and the Trash path unregistered. Original path is gone, final process/LaunchServices/Spotlight checks expose no original temporary fixture; the main app hash is unchanged. No real saved tasks or preferences were changed.


## Movement scrolling and reveal — Task 7 (2026-10-07)

**Native acceptance: BLOCKED.** The isolated fixture uses production state/controller/view, SQLite `/private/tmp/menupocket-task7-native/notes.sqlite`, defaults suite `local.menupocket.task7-presentation`, injected October 7 Toronto clock, and no production delegate/login/hotkey initialization. It contained 60 Work tasks, a collapsed Home task, General task and empty category, in the initial Dark 800 × 560 pt window.

Initial fixture executable SHA-256: `a37070b2f662d3968c78693a0682aad708ade3ef9089b771b7aad3eebf5361ac`, observed exact-path PID 34935. A handle drag exposed transient destination feedback; the first Escape removed its footer. A second attempt toward the bottom edge exposed the footer but did not establish sustained viewport scrolling or a saved native drop; later Escape/close automation timed out. SQLite order remained unchanged at that point. This fixture was stopped and cleaned before final rebuilding.

Final executable SHA-256: `9e94882b6e1e661a3223ac9baf845dc2b55e4bca725bb53b04173a4075676379`, observed exact-path PID 38381. A fixture-only native menu/shortcut calls `DailyNotesState.moveTask` to move Work task 1 to Home; SQLite confirmed destination UUID `7D2B2987-829A-4271-AC3E-4C1EDF32D153`, daily rank 60. However native menu tracking then returned stale accessibility IDs and unavailable window screenshots, so the saved command does **not** establish visible offscreen/collapsed destination reveal, successful dragging, or Task 8 production menu acceptance. No screenshot files are claimed; initial screenshots were inspected inline.

| Scenario | Result |
| --- | --- |
| Isolated long-list interface startup | Pass |
| First handle drag feedback / Escape clears temporary footer | Observed on initial artifact; final-artifact drag retest not established |
| Sustained edge scrolling, above/below viewport and cancellation while scrolling | Blocked |
| Successful saved native drop | Blocked |
| Fixture-only common saved command changes isolated SQLite assignment/order | Pass; narrower than native dragging or visible reveal |
| Visible collapsed/offscreen row reveal, focus/ring and failed/interrupted jump behavior | Blocked |
| Integrated close/reopen, rollover, removed destination and unavailable-read recovery | Not tested in the real interface; hosted checks are separate |
| Oldest supported OS, minimum window, full changed-data relaunch | Not tested; later acceptance cards retain these checks |

Final [automated/review evidence](DESKTOP_TASK_REGRESSION.md#movement-scrolling-and-reveal--task-7-2026-10-07) is 69/69 author tests and 6/6 independent checks. Both fixture processes and all created temporary hosts were stopped/unregistered/trash-moved; original paths gone and main app hash unchanged. No real user task data or preferences were modified. Resolve native drag/drop/scroll/reveal observations before closing Tasks 6/7 acceptance.

## Native movement source — Task 5 (2026-10-07)

**Native source acceptance: Pass on macOS 26.6.2 (user-operated).** The isolated fixture `/private/tmp/menupocket-task5-native/DragSourceFixture.app` (executable SHA-256 `c74879fd7e522a1d40af1fd065c2abfaed2ba4b34aff8f9b42c1c480b63ae4c5`, PID 91645, source ignored `build/task5/DragSourceFixture.swift`, built from HEAD `0502d41`) used production `TaskWindowController`/`TaskWindowView`, SQLite in that folder, defaults suite `local.menupocket.task5-presentation`, an injected 2026-10-07 Toronto clock, and no app delegate or login/hotkey services. A fixture-only status panel showed the live `active` payload and `isDragging` reservation. Data: Work (one open, one completed), Home, empty category, and one long General task.

| Scenario | Result |
| --- | --- |
| Open-hand cursor on the handle; drag shows a task-shaped preview; session becomes active/reserved | Pass |
| Escape mid-drag: preview returns, session clears (`active: none`, `reserved: false`), transient empty groups disappear | Pass |
| Release outside the window: same clearing, no task change | Pass |
| Completed task preview shows checked box and secondary text | Pass |
| Checkbox, text selection/⌘C and ⋯ menu do not start a drag | Pass |
| Click on the handle without movement does not start a drag | Pass |
| Handle disabled and no drag while another task is in inline edit | Pass |
| Oldest supported OS (macOS 14) runtime | Not tested (no environment) |

The user performed and reported these observations; Claude did not operate the interface. The fixture process was stopped, unregistered, moved to Trash with `FileManager.trashItem`, and the Trash path unregistered (`build/task5/cleanup-final.txt`); no real tasks or preferences were changed. Saved native drops, insertion feedback and edge scrolling remain Task 6/7 acceptance work.

## Movement destinations, scrolling and reveal — Tasks 6/7 native acceptance (2026-10-07)

**Native acceptance: Pass on macOS 26.6.2.** The isolated fixture `/private/tmp/menupocket-task67-native/MovementFixture.app` (executable SHA-256 `d04f841fd94d758fd91c43937b291d0bc83b0055aa149c695e84fb41437878b3`, source ignored `build/task67/MovementFixture.swift`, built from HEAD `14cf694`) used production `TaskWindowController`/`TaskWindowView`, SQLite `/private/tmp/menupocket-task67-native/notes.sqlite`, defaults suite `local.menupocket.task67-presentation`, an injected 2026-10-07 Toronto clock, and no app delegate or login/hotkey services. Seed: Work W01–W60 (W02 completed), collapsed Home (H1), an empty category, General (G1), in the initial 800 × 560 pt Dark window. A fixture-only status panel showed the live session, the hovered request, and the order read back from SQLite.

Steps 1–4 were operated by Claude through Computer Use; steps 5–15 were performed and reported by the user. The SQLite state was checked against each report.

| # | Scenario | Result |
| --- | --- | --- |
| 1 | Escape during hover clears line, transient groups and session; nothing saved | Pass (Claude) |
| 2 | Row lower half: W05 after W01; saved `W01 W05 W02 …` | Pass (Claude) |
| 3 | Row upper half: W06 before W01; saved `W06 W01 W05 …` | Pass (Claude) |
| 4 | Equivalent placement (W03 after W02): no line, `hover: none`, no write | Pass (Claude) |
| 5 | Category → General header (end of group) | Pass (user) |
| 6 | General → category row | Pass (user) |
| 7 | Transient Empty category accepts a drop | Pass (user) |
| 8 | Collapsed Home header accepts without expanding on hover; expands after save | Pass (user) |
| 9 | Completed task keeps completion; overall progress unchanged | Pass (user) |
| 10 | Bottom-edge scrolling, bounded and stops away from the edge | Pass (user; also observed by Claude) |
| 11 | Top-edge scrolling and drop | Pass (user) |
| 12 | Escape while edge-scrolling stops scrolling | Pass (user, physical mouse) |
| 13 | Offscreen collapsed destination expands and reveals the moved row | Pass (user) |
| 14 | No unexpected keyboard focus ring after pointer drops | Pass (user) |
| 15 | ⌘Q, confirmed exit, relaunch without reseeding: order/groups match | Pass (user) |

Final SQLite after the user session (written 16:34): Work 56 tasks (`W01 W05 W03 W04 W07 …`), Home `H1 W59`, Empty `W60`, General `W02 W06 G1`; 62 tasks, W02 is still the only completed task. Record: ignored `build/task67/final-saved-order.txt`.

Automation-only observations, not reproduced by the user's physical-mouse pass: when one Computer Use drag spanned two tool calls, the synthetic mouse-up did not reach AppKit's drag loop. The preview froze, `isDragging` stayed true, and the fixture spun at ~100% CPU in `NSCoreDragManager _dragUntilMouseUp` with continuous SwiftUI re-rendering (`build/task67/stuck-sample.txt`). Synthetic Escape during edge scrolling also let scrolling continue for about four rows during the cancel slide-back. During normal drags CPU was 33–87% while scrolling and ~0.5% idle (`build/task67/cpu-log.txt`). Drop targets request periodic dragging updates and re-assign `hoveredRequest` on every update, which re-renders observing rows even when the value is unchanged. This is a possible efficiency improvement, not an acceptance failure.

Not tested: oldest supported OS (macOS 14), the 600 × 400 pt minimum window, a failed-write drop in the real interface, and the 1,000-task scale probe (TASK-009/010). The fixture was killed twice after stuck automation drags; saved data was intact both times. It was finally moved to Trash with `FileManager.trashItem` and unregistered (`build/task67/cleanup-final.txt`); `/Applications/MenuPocket.app` executable hash is unchanged. No real tasks or preferences were modified.

## Row-menu movement — Task 8 (2026-10-07)

**Native acceptance: Pass on macOS 26.6.2 (user-operated).** The isolated fixture `/private/tmp/menupocket-task8-native/MovementFixture.app` (source ignored `build/task8/MovementFixture.swift`, HEAD `ee47259` plus the uncommitted Task 8 change) used production `TaskWindowController`/`TaskWindowView`, SQLite in that folder, defaults suite `local.menupocket.task8-presentation`, an injected 2026-10-07 Toronto clock, and no app delegate or login/hotkey services. Seed: Work W01–W12 (W02 completed), collapsed Home (H1), a category with a 68-character name, and General (G1).

| # | Scenario | Result |
| --- | --- | --- |
| 1 | Tab + Space opens Edit / Move Up / Move Down / Move To ▸ / Delete… | Pass |
| 2–3 | Move Up/Down by keyboard; focus stays on the row's actions | Pass |
| 4 | Boundary items disabled (top, bottom, single-task group) | Pass |
| 5 | Move To: current group checked/disabled, long label acceptable; collapsed Home expands and reveals | Pass |
| 6 | General → Work → General | **Fail, then Pass after repair** (below) |
| 7 | Completed task keeps completion; progress unchanged | Pass |
| 8 | Moves unavailable during inline edit | Pass |
| 9 | Edit, Delete… and checkbox Space still work | Pass |
| 10 | ⌘Q and relaunch keep the saved order | Pass |

Step 6 initial failure (fixture executable `ceff298f…`, 811 × 430 pt window): moving G1 back into a re-created, last General group left the list area blank until the user scrolled. Claude reproduced the setup in a separate debug fixture. One capture right after the move was blank, but the persistent blank was not reproduced, so the root cause is unconfirmed. Repair: the saved-move reveal now scrolls minimally (`scrollTo` without `.top`/`.center` anchors), so it never targets an offset past the end of the content. This also applies to drag reveal. On the repaired fixture (`65c9a5b7…`), the user reported step 6 and steps 7–10 Pass. Final SQLite (17:17): Work `W01 W02 W03 W04 W06 … W12`, Home `H1 W05`, General `G1`; 14 tasks, W02 the only completed task (`build/task8/final-saved-order.txt`).

Claude used background Computer Use only on the separate debug fixture (`/private/tmp/menupocket-task8-debug`, now trashed) and took read-only screenshots of the user's fixture. Not tested: VoiceOver spoken output, macOS 14, and the 600 × 400 pt minimum. Every fixture was stopped, unregistered and moved to Trash, with Trash paths unregistered (`build/task8/cleanup-*.txt`); `/Applications/MenuPocket.app` executable hash is unchanged. No real tasks or preferences were modified.

## Movement native acceptance — Task 10 (2026-10-08)

**Native acceptance: partial on macOS 26.6.2; drag-dependent and system scenarios remain Not tested.** Isolated fixture `/private/tmp/menupocket-task10-native/MovementFixture.app` (bundle `local.menupocket.task10.fixture`, executable SHA-256 `3042bf4ee05ec2b30b802eb9d49ac58e649aa9680965a94565abef627f3c72e4`), built from clean `main` `1775a38` (PR #49 merge) with every production source except `MenuPocketApp.swift` plus ignored harness `build/task10/FixtureMain.swift` (SHA-256 `66762d57…`): Swift 6.4 (Xcode 27.0, `27A266a`), `-Onone`, macOS 14 arm64 target, ad-hoc signed. Unlike the Task 5–8 fixtures it runs the production `AppDelegate`, so the status item, glance, Quick Add panel, Later tab and History are live. Each scenario (`main`, `scale`) has its own SQLite file under `/private/tmp/menupocket-task10-native/data/` and defaults suite `local.menupocket.task10-presentation.<scenario>`; fixed Toronto clock Thursday, October 8, 2026 12:00 with a shell-driven day offset; fake login item; a fake Quick Add hotkey pressed by `SIGUSR1`; flag files injecting move-write and Today-read failures. `lsof` showed only the isolated database open. PIDs: 49125 and 67895 (`main`, before and after relaunch), 68400 (`scale`), 69853 (`main`). Dark appearance, 800 × 612 pt window. Seed `main`: Work W01–W14 (W02 completed, W04 long text), collapsed Home (H1, H2✓), empty Errands, a 78-character category (L1), General (G1), Later LA (Work), LB, LC✓, and two tasks on October 7. Seed `scale`: 1,000 tasks interleaved across C01–C09 and General, every seventh completed.

The user operated A1–A4 with a physical mouse and typed one Quick Add. Claude operated the other checks through background Computer Use, limited to the fixture bundle. Each saved result was checked against SQLite.

| # | Scenario | Result |
| --- | --- | --- |
| A1 | Escape mid-drag clears line and temporary group; nothing saved | Pass (user) |
| A2–A3 | Row lower/upper half within Work: `W01 W05 …`, then `W06 W01 W05 …` | Pass (user; SQLite and window) |
| A4 | Equivalent placement: no line, no write | Pass (user) |
| — | Cross-category row drop General → long category | Saved once by a Claude single-motion drag (G1 joined the category with fields and completion unchanged), but it landed before L1 rather than the intended after. Drop placement is recomputed from the pointer at drop time; with no visible line in a sub-second synthetic drag, the target half is **inconclusive**, not a placement failure |
| — | Three further Claude single-motion drags (no visible target, temporary Errands footer, collapsed Work 2 header) | No drop landed. Each cancelled cleanly: temporary groups cleared, no write, process idle, draft unchanged. Successful empty/collapsed-destination drops are **Not tested** here |
| B3 | Checkbox toggles `3/18` → `2/18`; no drag | Pass (accessibility press; physical click covered in Task 5) |
| B4 | Text selection by dragging across task text; no task drag | Pass. ⌘C Not tested (tool refuses clipboard menu items; covered in Task 5) |
| B5 | Edit → Cancel and Delete… → Cancel | Pass; new-task draft kept |
| C1 | Space on a focused ⋯ opens Edit / Move Up / Move Down / Move To ▸ / Delete… | Pass |
| C2 | Keyboard Move Up then Move Down; menu reopens at the row's new position | Pass (saved `W01 W06 …`, then `W06 W01 …`) |
| C3 | Move Up disabled at the top of a group; both disabled in a one-task group | Pass. Bottom-of-group menu fell outside the captured window |
| C4–C5 | Move To submenu, current group checked/disabled, long label, collapsed destination | **Not tested**: the submenu opens outside the window, beyond background control |
| D1 | Inline edit blocks dragging another task; handle and ⋯ dimmed | Pass |
| D2 | Delete confirmation blocks dragging | Pass |
| D3 | Category manager blocks dragging | **Not tested** natively (window-modal sheet; tool would not deliver the drag) |
| E2 | Quick Add with another app frontmost appends after the reordered day (rank 18, end of General), `2/19`; Today draft kept | Pass (user keystrokes). Two earlier panels closed on focus loss by design and saved nothing |
| E3 | Later rows have no handle; Later ⋯ = Move to Today / Edit / Delete… | Pass |
| E4 | Later → Today after reordering: LA appended to the end of Work 2 (rank 19); `2/20` | Pass |
| E6 | Row-menu Move Up then History: saved `W06 W05 W01 …`; History stays open; Today shows no error afterwards | Pass |
| E7 | Rename Work → Work 2 keeps order; removing Home merges into General in saved daily order `G1 H1 H2✓ QA1`; stale collapsed ID pruned | Pass |
| E8 | Injected Today read failure: close and Show Tasks → "Tasks are unavailable" + Retry, no rows/handles; Retry restores saved order; draft kept | Pass |
| F1 | ⌘Q, confirmed exit, relaunch of the same artifact without reseeding | Pass. Full dumps (schema, rows with rowids, ranks, fields, defaults) before quit, while stopped and after relaunch are identical; the window shows the same groups/order; the blank composer shows General. The unsaved draft is not kept (process-local) |
| G1 | Idle rollover to Friday, October 9: empty Today, date-changed notice, "18 unfinished tasks from yesterday" | Pass |
| G3 | Day reset returns to October 8; store unchanged by rollover/reset | Pass |
| H1 | 1,000 tasks: seeded in ~4.4 s; scrolled top, middle and end; keyboard Move Up saved `S0970 S0990 S0980 S1000` within a second; process idle afterwards | Pass. Hosted latency remains the Task 9 probe (15.6 ms median) |

**Not tested** (no user or tool observation in this session): cross-category row/header drops with a visible insertion line, transient empty General and custom destinations, collapsed-header drop, completed-row drag, outside-window drop, failed-write drop (A5–A15); bottom/top edge scrolling and Escape while scrolling (A16–A18); 600 × 400 pt minimum window and Light/Dark drag feedback (A19–A20); draft and category choice during a drag (D4); ⌘2 and rollover during a drag (E5, G2); glance order after moves (E1); 1,000-task edge-scrolled drag (H2); VoiceOver; macOS 14. Tasks 5–8 native records cover several of these on the pre-merge branch; they are not re-established on the merged build.

Automation-only observations: an accessibility press on History, delivered before the row menu's queued Move Up ran, made that move hit the History guard and show "Could not move task. Try again." with no write. A physical click cannot precede that dispatch; with realistic timing E6 passed. Background menus sometimes closed before keystrokes arrived; those attempts changed nothing.

Cleanup: the fixture was quit (no process), unregistered from LaunchServices, moved to Trash with `FileManager.trashItem` (2026-10-08T05:51Z), and the Trash path unregistered. The original path is gone and neither LaunchServices nor Spotlight lists the bundle. `/Applications/MenuPocket.app` (executable `41b7a235…`, PID 99856) was not touched. Fixture data and its defaults suites are isolated test data. Evidence: ignored `build/task10/` (`MANUAL_CHECKS.md`, `RESULTS.md`, `artifact-identity.txt`, `session-identity.txt`, dumps, `cleanup-final.txt`).

## Movement acceptance summary — Task 11 (2026-10-08)

**Movement acceptance: partial.** This section brings together the Task 5–10 native records above for the handoff. It adds no new observations: Task 11 built, ran, and tested nothing. Saved task movement (REQ-017) was merged into `main` by nstnn/MenuPeek#49 at `1775a38720939db5e47792bcb4aa66d6c0bf669b`. `main` later gained only the Task 10 documentation (`2290aa2`, nstnn/MenuPeek#50), so the app source is unchanged since `1775a38`. Automated and CI evidence is in [Desktop regression](DESKTOP_TASK_REGRESSION.md#movement-feature-handoff--task-11-2026-10-08). On 2026-10-08 the user asked to proceed with Task 11, so the Task 10 gaps below are recorded as open rather than tested.

The Task 5–8 fixtures ran production window, view, and state code from the pre-merge `feat/task-movement` branch without the app delegate, Later tab, or History. The Task 10 fixture ran the merged build with the production `AppDelegate`. All sessions ran on macOS 26.6.2 with isolated SQLite and defaults. A dash means the scenario did not exist on that build.

| Scenario | Pre-merge fixtures (Tasks 5–8) | Merged build (Task 10) |
| --- | --- | --- |
| Handle drag start, task-shaped preview, cursor | Pass (T5) | Pass (A1–A4, user) |
| Escape mid-drag clears feedback, temporary groups, and session | Pass (T5; T6/7 #1) | Pass (A1, user) |
| Release outside the window cancels | Pass (T5) | Not tested |
| Row lower/upper half within a group | Pass (T6/7 #2–3) | Pass (A2–A3, user) |
| Equivalent placement offers no target and writes nothing | Pass (T6/7 #4) | Pass (A4, user) |
| Cross-group row drop | Pass (T6/7 #6) | Inconclusive: one synthetic drop saved once, row half not established |
| Header drop places at the end of a group | Pass (T6/7 #5) | Not tested |
| Temporary empty custom destination | Pass (T6/7 #7) | Not tested |
| Temporary empty General destination | Not tested | Not tested |
| Collapsed header accepts without expanding on hover, expands after save | Pass (T6/7 #8) | Not tested |
| Completed task keeps completion; progress unchanged | Pass (T6/7 #9 drag; T8 #7 menu) | Not tested |
| Top and bottom edge scrolling; Escape while scrolling | Pass (T6/7 #10–12) | Not tested |
| Offscreen collapsed destination revealed | Pass (T6/7 #13 drag; T8 #5 menu) | Not tested |
| No keyboard focus ring after pointer drops | Pass (T6/7 #14) | Not tested |
| Checkbox, text selection, and ⋯ do not start a drag; Edit/Delete work | Pass (T5; T8 #9) | Pass (B3–B5; Command-C not tested) |
| Click on the handle without movement does nothing | Pass (T5) | Not tested |
| Keyboard ⋯ menu, Move Up/Down, focus follows the row | Pass (T8 #1–3) | Pass (C1–C2) |
| Move Up/Down disabled at group boundaries | Pass (T8 #4) | Pass (C3; bottom boundary not captured) |
| Move To: current group checked and disabled, long label, collapsed destination | Pass (T8 #5) | Not tested (C4–C5) |
| Move into a re-created last group reveals the row | Fail, then Pass after the minimal-scroll repair (T8 #6) | Not tested |
| Inline edit blocks moving | Pass (T5; T8 #8) | Pass (D1) |
| Deletion confirmation blocks dragging | Not tested | Pass (D2) |
| Category manager blocks dragging | Not tested (hosted only) | Not tested (hosted only) |
| Draft and category choice kept during a drag | Not tested | Not tested |
| Command-2 or a day change during a drag | — | Not tested |
| Row-menu move, then History | — | Pass (E6) |
| Later rows have no handle; Later ⋯ menu | — | Pass (E3) |
| Later Move to Today and Quick Add append after a reorder | — | Pass (E2 user keystrokes, E4) |
| Category rename and removal keep saved order | — | Pass (E7) |
| Unavailable Today read, then Retry | — | Pass (E8) |
| Injected failed write shows the move error and keeps data | Not tested | Not tested |
| Changed-data Command-Q and relaunch of the same artifact | Pass (T6/7 #15; T8 #10) | Pass (F1, identical full dumps) |
| Idle day rollover and reset | — | Pass (G1, G3) |
| 1,000 tasks: scrolling and a keyboard move | — | Pass (H1) |
| 1,000-task drag with edge scrolling | — | Not tested |
| Menu bar glance order after a move | — | Not tested |
| 600 × 400 pt minimum window | Not tested | Not tested |
| Light appearance (recorded sessions were Dark or did not record it) | Not tested | Not tested |
| VoiceOver | Not tested | Not tested |
| macOS 14 | Not tested | Not tested |
| Production-identity app, App Sandbox, first real-data v4 upgrade | Not tested | Not tested |

Remaining movement acceptance gate:

1. On a fixture built from the current source, with a physical mouse, re-establish the pre-merge drag results on the merged build: cross-group row and header drops with a visible line, empty custom and General destinations, a collapsed header, a completed row, an outside-window release, edge scrolling with Escape, and offscreen reveal. Then exercise the scenarios never observed: an injected failed write, a draft during a drag, Command-2 and a day change during a drag, the category-manager guard, glance order, Move To on the merged build, and a 1,000-task drag.
2. Check the 600 × 400 pt minimum by a real window drag, Light appearance, and VoiceOver (handle label, menu hint, Move items). Record macOS 14 as Not tested unless a macOS 14 environment is available.
3. Before the first real-data launch of a v4 build, follow [Schema v4 upgrade preparation](WORKFLOW.md#schema-v4-upgrade-preparation). A production-identity observation needs its own identified artifact.

Open issue found during Task 11 by source inspection, not reproduced in the interface: a committed move does not advance `historyRevision`. A History day detail already loaded for Today can therefore keep its pre-move grouping and order until the next refresh ([Architecture](ARCHITECTURE.md#history-read-facade-and-invalidation)). Counts are unaffected.

Cleanup: Task 11 created no app bundle, ran no fixture or test host, and changed no saved data, so it needed no artifact cleanup. Every earlier session's cleanup is recorded in its own section.


## Movement follow-up — interrupted scroll verification (2026-10-08)

Session in progress, not full acceptance. The user requested completing Tasks 10/11 and guided physical checks. A new isolated fixture `/private/tmp/menupocket-task10-final-native/MovementFixture.app` uses bundle `local.menupocket.task10.final.fixture`, separate data/defaults, production AppDelegate and fake system services. First artifact executable `4a45ef278ea94ec7f8093dfd2f69d75ff212b8861ebe7f7f166641a05cb61793` includes the History invalidation repair. User physically passed row lower/upper halves, equivalent no-op and Escape. SQLite confirmed Work `W06 W01 W05 W02✓ W03…`; no-op/Escape schema/rows/defaults dumps were identical. These observations preceded the scrolling repair and are not blanket acceptance of the later artifact.

Before cross-group step 5, the fixture stopped; no saved change or corrupted data was observed (`integrity_check=ok`). Logs indicate termination and a hang dialog. A reopened fixture then used ~100% CPU; a sampled main-thread stack was in SwiftUI/AttributeGraph updates. A diagnostic variant idled at startup but ordinary user scrolling reproduced the hang. The user's later screenshot/clarification identifies ordinary scrolling, not drag/drop, as the trigger; machine load was an earlier unverified hypothesis.

The minimal final source repair changes group `LazyVStack` to `VStack`, preserving existing scroll-position/reveal behavior. Earlier diagnostic variants and the passive-geometry attempted patch were discarded after a reveal hang and are not shipped. Final fixture executable `b21e2ff984e7bac91af60194fc22e15a3e4b0223c31f4b81bba8f01d116e5637` responds to mid-list and bottom scrolling via Computer Use, with idle CPU after observation. Eager diagnostic variant also passed menu movement/recreation of General with focus following G1; this is narrower than a final-artifact observation. G1 restored to General before resuming the user's guide. Full final hosted suite 404/404 and Release pass; logs/results/review input under `build/task10-final/`.

The active final fixture is retained only for this ongoing guided session. Completed test hosts and replaced/stopped diagnostic bundles were unregistered and trashed; main app hash remains `41b7a235259fd71e04a04882c094253e25b7daad8c17597164ea9f2c677a1aed`. Final fixture cleanup and remaining native scenarios are pending; Task 10 is not complete.

User subsequently reports step 5 Pass on the eager-group artifact: L1 is saved in Work immediately before W03. G1's move into the long-name category was intentional, as clarified by the user. The next reported gap is the left six-dot handle's hand cursor after scrolling/dropping. A visible-rect tracking area was added to `TaskDragHandleView`; updated fixture executable `af2aa412571af88f0336c67e1b43a0132a79abd86f8f67c5eadd1cfb75f01069` is open for physical hover checks. Cursor acceptance is pending, including leaving the handle and hover after a drop. Updated hosted suite passes 404/404; Release passes. Replaced fixture and completed hosts were cleaned; the active fixture belongs to the continuing manual session.

Physical hover on `af2aa412…` failed: the user still sees no hand cursor. The cursor tracking change is not an accepted repair; diagnostic investigation continues. Step 5 remains a saved-move Pass, independent of this feedback defect.

The user explicitly deferred cursor verification during this session to prioritize the remaining feature acceptance scenarios. The current candidate confines the native handle with `clipsToBounds = true`; automated checks pass, but cursor behavior is **Deferred by user**, not Pass. Other native movement checks continue.

## Movement follow-up — session closure with user-accepted gaps (2026-10-08)

The user reports physical steps 6 and 7 Pass and explicitly asks to stop further manual checks because of the time required. Cursor verification was already deferred. Task 10's verification handoff and Task 11's evidence handoff are closed within this reduced scope. This is not a claim that every original native/system criterion passed.

| Follow-up scenario | Result / evidence |
| --- | --- |
| Row lower/upper placement | Pass, user physical steps 1/2; SQLite confirms order on the first artifact |
| Equivalent no-op and Escape | Pass, user physical steps 3/4; saved dumps identical on the first artifact |
| Ordinary scrolling after layout repair | Pass, responsive native AX and idle CPU on eager-group fixture |
| L1 into Work before W03 | Pass, user step 5 and SQLite on eager-group fixture |
| Long W04 into empty General header | Pass, user step 6; SQLite and AX confirm General contains W04 |
| G1 from Errands into Work after W06 | Pass, user step 7; SQLite and AX confirm `W06 G1 W01…` |
| Retained History invalidation after move | Automated Pass, real SQLite/retained-presentation regression; no new final-artifact physical History acceptance |
| Hand cursor on hover | Deferred by user; unclipped candidate failed; clipped candidate's physical behavior unverified |
| Remaining original native scenarios | Not tested in this follow-up / skipped by user; earlier dated results retain their own artifact boundaries |

Final observed fixture executable SHA-256 `9062af8128be3acfa5588a6913f47f22f58a1b0bdb272b82b989f2967dfc0ee2` uses the current production sources plus `FixtureCursorProbe.swift`, a diagnostic pointer-state timer, fake system services and isolated fixed-clock storage. It is not the production-identity sandboxed app. Snapshot `build/task10-final/after-steps6-7.txt` preserves schema, rowids, saved fields/ranks and scoped defaults. Final five-file code/test diff SHA-256 `9fb2196dd2757ba7d1c89a6e1561a612b0d19400101262eb56095ac01fdff992` against `c0853af`; `ClippedCursor.xcresult` passes 404/404 with zero failures/skips, and Release build passes. Independent review found no confirmed source defect but native cursor evidence remains deferred. No full-feature READY verdict is inferred.

Outstanding original criteria include final-source sustained edge scrolling/1,000-task drag, collapsed/completed/outside drops, injected failed writes and mid-drag draft/tab/day/modal guards, final-source reveal/relaunch and glance checks, minimum size, Light appearance and VoiceOver. macOS 14, production identity and first real-data v4 upgrade remain Not tested. Earlier observations for these paths are preserved above, not transferred to this revised artifact.

Cleanup completed: fixture exited via Command-Q; no exact-path fixture process remains. Final fixture and Debug/Release hosts were unregistered and moved to Trash via `FileManager.trashItem`; resulting Trash paths were unregistered. Original bundle paths are absent. Logs `cleanup-session-final.log` and `cleanup-clipped-cursor-hosts.log` preserve identities. Logs, test results, isolated SQLite/defaults and snapshots remain available; no app bundle remains at the original test paths. Main `/Applications/MenuPocket.app` executable hash stays `41b7a235259fd71e04a04882c094253e25b7daad8c17597164ea9f2c677a1aed`. No production data, real login/hotkey registration, commit, push or PR was changed.
