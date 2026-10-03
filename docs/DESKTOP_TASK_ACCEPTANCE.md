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
