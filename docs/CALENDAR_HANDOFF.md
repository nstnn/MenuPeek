# Calendar — 2026-11-19

## Contract

A Calendar entry above History in the task window's sidebar opens a Day, Week (default) or Month view of time blocks in the right content column. A block is a title, one day, and a start and end time on the 15-minute grid within that day. Blocks are created with New block, a click on empty grid space, or a drag on the grid; edited and deleted in a popover editor; moved by dragging their body; and resized by dragging their lower edge. Month lists each day's first blocks with `+N more`, and choosing a day opens it in Day view. Blocks are saved in the local SQLite store and never link to tasks or categories. The full contract is in [Requirements](REQUIREMENTS.md#calendar--implemented-2026-11-19) and the component design in [Architecture](ARCHITECTURE.md#calendar).

Not built, and not to be described as existing: repeating blocks, copy day or week, block colours or categories, links to Today/Later tasks, blocks in the menu bar count or glance, notifications, a second time zone, blocks that cross midnight, drags in Month or to a day outside the visible week, a saved view or period, sync, import, export, or EventKit.

## Schema v6 and the one-way upgrade

Schema v6 adds one table, `schedule_blocks`, and its `day_key` index to the existing `notes.sqlite`. The table has no foreign keys. Known unversioned/v1–v5 stores upgrade in the existing single transaction; no task, Later, or category row, rank, rowid, or schema definition changes (hosted tests check that every prior row, rowid and schema definition of a v5 file is identical after the upgrade). A failed v6 step rolls back schema, data, and version. Malformed v6 files and files labelled 7+ are refused unchanged.

**The upgrade is one-way.** Once a v6 build has opened a database, every older build (v1–v5) refuses it. Before the first real-data launch of a v6 build, quit every MenuPocket copy and back up the database as described in [Schema v6 upgrade preparation](WORKFLOW.md#schema-v6-upgrade-preparation). No real-data upgrade was performed during this work; every check used temporary databases or fixture copies.

## Source

All Calendar changes are merged into `main`. The local plan is `plan/calendar/` (ignored by Git).

| Plan cards | Pull request | Merged | Content |
| --- | --- | --- | --- |
| TASK-001 | nstnn/MenuPeek#83 | 2026-11-16 | `ScheduleBlock`, `ScheduleBlockContent`, `ScheduleRepository` |
| TASK-002 | nstnn/MenuPeek#84 | 2026-11-16 | Schema v6 migration and validation |
| TASK-003 | nstnn/MenuPeek#88 | 2026-11-18 | SQLite block reads and writes |
| TASK-004–009 | nstnn/MenuPeek#89 | 2026-11-19 | Period math, grid geometry, `ScheduleState`, sidebar route, Day/Week grid, block editor |
| TASK-010 | nstnn/MenuPeek#90 | 2026-11-19 | Month view |
| TASK-011 | nstnn/MenuPeek#91 | 2026-11-19 | Drag to draw and resize |
| TASK-012 | nstnn/MenuPeek#92 | 2026-11-19 | Drag to move |
| TASK-013 | nstnn/MenuPeek#93 | 2026-11-19 | `db.txt` block rows and recipe corrections |

The entitlements file (`MenuPocket/App/MenuPocket.entitlements`) is unchanged since before TASK-001, and the Xcode project gained only Calendar source and test file entries: no package, framework, permission, or service was added.

## Automated verification

Each change ran its own hosted XCTest selection with the shared `MenuPocket` scheme; logs are under `build/logs/` (ignored).

| Change | Result |
| --- | --- |
| #83 | Full hosted suite 470/470. |
| #84 | Full hosted suite 476/476 (Xcode 27, macOS 26). An earlier run had one unrelated scroll-position failure that passed on rerun. |
| #88 | `SQLiteNoteRepositoryTests` and `ScheduleBlockTests`, 98/98. Full suite not run. |
| #89 | Calendar classes and `AppConfigurationTests`, 159/159 on the final source, with `testComposerKeepsNativeUndoAcrossRepeatedRequestsAndWindowReopen` run separately as in CI. Earlier commits ran 214 tests including `DailyNotesStateTests`, `TaskHistoryIntegrationTests` and `TaskWindowZoomTests`. No 200 ms type-check warnings in Calendar files. |
| #90 | All `Schedule*` classes, 105/105. |
| #91 | Calendar classes, 123/123. The later auto-scroll and cursor fixes are view/AppKit code checked in the running app. |
| #92 | Full hosted suite 616/616. |
| TASK-015, `c552c3f` (`main` after #94), clean | Full hosted suite run as CI runs it: 615/615 with the composer Undo test skipped, then that test alone 1/1; 0 failures, 0 skipped (Xcode 27.0, macOS 26.6.2). Release build succeeded. A `build-for-testing` with the 200 ms type-check warnings flagged six functions, none in a Calendar file (`TaskHistoryCalendarView.dayCell` 791 ms, `TaskWindowView.groupHeader` 322 ms and `body` 265 ms, `TaskActionsPopover.itemView` 269 ms, `CategoryDragSession.canBegin` 242 ms). GitHub CI `Build and test` passed on #94 and on the `main` push of `c552c3f`. Logs: `build/logs/task015-20261119-144927-*`. |

## Native verification

All interface checks used the isolated `verify-menupocket` fixture with seeded synthetic data, the clock fixed at 2026-11-18 10:00 America/Toronto, and the [Calendar recipe](../.agents/skills/verify-menupocket/features/calendar.md). They are fixture observations, not production acceptance. Evidence lives under `build/verify-menupocket/evidence/<run>/` (ignored).

| Run | Source | Operated by | Result |
| --- | --- | --- | --- |
| 20261118-162059 (`--seed basic`) | TASK-007 working tree | Agent | Pass: sidebar order and rule; open from Today and Later with the list kept; header navigation and view switch; every entry leaves Calendar; edit, deletion and rename disable it; browsing leaves `db.txt` unchanged; a simulated open failure shows Unavailable and Retry recovers. |
| 20261118-163913 (final for TASK-008; 163256 and 163609 superseded) | TASK-008 working tree | Agent | Pass: all 11 seeded blocks in the right column and time; overlaps side by side; current-time line only in today's column; Day view; initial scroll; Dark and (run 163609) Light; 150% zoom after a column-sizing fix. |
| 20261118-201144 (170358 and 171651 superseded) | TASK-009 working tree | Agent, then user | Agent: New block prefill and save; empty-title message; edits of title, day, start and end; Escape/Cancel write nothing; delete with Cancel and confirm; a simulated write failure keeps the input; quit and relaunch keep all 12 rows. User: slot click creates a block, a click outside only closes, the outline follows From, a click on a block opens it. The 170358 run found the dismissing-click bug, since fixed. |
| 20261118-203606, 203814 | TASK-010 working tree | Agent | Pass: one button per day, labels and values match the rows, `+N more` at 88 pt cells and at 150% zoom, a day opens Day view and is outlined on return, Previous/Next step by month. |
| 20261118-205440 to 20261119-012007 | TASK-011 working tree | Agent and user | Pass: drawing 10:00→11:30 saves `600\|690`, drawing upward gives the same span, resizing to 12:15 and above the start, a click on empty space opens 13:00–14:00. User: Escape mid-draw and mid-resize, auto-scroll at both edges, the resize cursor, and a resize during a held SQLite lock showing `Could not save block changes. Try again.` Three bugs found here were fixed before merge. |
| 20261119-121533 | `f8bf06e` (#92 merged), clean | Agent | Integrated recipe run: sidebar order; open from Today and Later; header navigation; Day/Week/Month; every exit; edit, deletion and rename guards; overlap frames; Month labels, values and the 1st's column at 100% and 150%; current-time line; 150% zoom fits; editor create, empty-title message, edit, keyboard move to Thursday 14:30 (`870\|930`); a held `BEGIN EXCLUSIVE` lock shows `Could not save block. Try again.` and Save then succeeds; browsing leaves the block rows unchanged; the block rows are identical after stop and relaunch; a simulated read failure shows `Could not load this week. Try again.` and Retry recovers; Light appearance. Cleanup trashed and unregistered the fixture bundle. |

The 121533 run also corrected the recipe (merged in #93): a From/To pop-up choice must be awaited before Save, the Month `+N more` expectation depends on zoom, and the lock command needs the full database path.

## Integrated regression and acceptance (TASK-015) — 2026-11-19

All runs below were built from clean `c552c3f` (no dirty app sources) and operated by the agent through `mpax` on isolated fixtures with the clock fixed at 2026-11-18 10:00 America/Toronto. The user chose not to perform pointer gestures in this session, so every drag and slot click is Not tested here.

### Calendar recipe — run 20261119-145100 (`--seed calendar`, executable `c5a668de3010…`)

| Check | Result |
| --- | --- |
| Sidebar order (Calendar, rule, History, Categories, Settings; `Open Calendar`) | Pass |
| Open from Today and from Later; Today/Later selection and rail values kept | Pass |
| Header: Week 47 → 46 → 48 → 47; `Previous week`/`Next week`/`Show today` labels | Pass |
| Day/Week/Month switch, headings and `Previous day`/`Next month` labels | Pass |
| Leave through History, Categories, Settings and Today, returning each time | Pass |
| Guards: Calendar disabled during a task edit, a deletion confirmation and a category rename; enabled after each cancel; an idle manager can be left for Calendar | Pass |
| Week grid: seven Monday-first headings, `, today` only on Wednesday; 11 block elements matching the 11 rows; Pairing 30 pt below Design review; Thursday thirds; touching Lunch/Focus full width | Pass |
| Current-time line `Current time, 10:00` only in the current week and only on today in Day view | Pass |
| Month: 30 day buttons, labels and values match the rows; the 1st in the Sunday column, six week rows; at 100% today shows four lines and Thursday three with no `+N more`; at 150% `10:00 Des…` `+3 more` and Thursday `+2 more`; a day opens Day view and is outlined back in Month; Next/Previous by month | Pass |
| 150% zoom: window 1200×872, grid, Next and the Sunday heading inside it; Actual Size returns to 1000×732 | Pass |
| Minimum window: an Accessibility size request of 600×400 (ad hoc helper, logged) was clamped to 800×592, a content size of 800×560. Week fits with all seven columns and the header; Month keeps six week rows with one line plus `+N more` per busy day | Pass |
| Light appearance (Theme set in Settings, then back to System): Week, Month and the New block popover | Pass |
| Read-only browsing: `db.txt` before and after navigating every view identical | Pass |
| Editor create (prefill Wednesday 11:00–12:00, `Duration 1 h`, title focused; empty-title message; `Write docs\|2026-11-18\|660\|720`; focus back on New block) | Pass |
| Editor edit (From 13:00 moves To to 14:00; To 12:00 moves From to 11:00; To 14:45 `3 h 45`; next day; rename; same UUID `Write the docs\|2026-11-19\|660\|885`; Return reopens it, Escape closes) | Pass |
| Delete: Keep block keeps the row, Delete block removes it; focus back on New block | Pass |
| Keyboard move: Design review to Thursday 14:30 through Next day and the From pop-up; a held `BEGIN EXCLUSIVE` lock shows `Could not save block changes. Try again.` with fields kept; Save after release writes `Design review\|2026-11-19\|870\|930` | Pass (simulated failure) |
| Busy editor: rail entries, Today tab and Settings disabled; Command-N leaves the editor open; Escape re-enables | Pass |
| Persistence: `db.txt` identical in the changed, stopped and relaunched snapshots; after relaunch the view is Week on week 47 and the 11 block elements are identical. Against the seed, only the intended block rows differ; every task, Later and category row is unchanged | Pass |
| Unavailable: with a simulated open failure the pane shows `Calendar is unavailable`, `Could not load this week. Try again.` and Retry; Retry after clearing the failure shows all 11 blocks | Pass (simulated failure) |

Observation, not a failure: with four overlapping columns on Thursday at 100% (after the edits) each block is about 30 pt wide and shows only `…`; the full title is in the label and hover text, as the contract allows.

### Upgrade of a copied v5 database — runs 20261119-144949 (v5) and 20261119-145207 (v6, executable `4852e03b3b76…`)

1. A fixture built from `fb58712` (last schema-v5 commit, executable `d45850b7d1d2…`) created a store with `--seed category-reordering`: 33 tasks, 4 Later tasks, 4 categories, `user_version` 5.
2. That store was copied with `sqlite3 .backup` (integrity `ok`) into a fresh v6 run's data folder and opened by the v6 fixture without a seed. This is the only seeded precondition, logged in `actions.log`.
3. After opening: `user_version` 6, integrity `ok`, `schedule_blocks` and `schedule_blocks_day_key_idx` added and empty. A dump of every `notes`, `later_tasks` and `categories` row with its rowid, and every prior `sqlite_master` entry, was identical to the v5 dump. The window showed `2 of 28 complete` and `4 tasks remaining`, as before.
4. New block saved `Upgrade check\|2026-11-18\|660\|720` on the upgraded store; after stop and relaunch the block was listed again and the task, Later, category and schema dump was still identical to the v5 dump.
5. One-way check: a copy of the upgraded v6 file opened by the v5 fixture failed with `unsupportedSchemaVersion(6)` and the file's SHA-256 was unchanged. The v5 fixture exits at that point because its harness opens storage at top level, so the v5 interface's Unavailable state was not observed.

Result: Pass. The user's real database was not opened, copied or upgraded.

### Regression recipes — run 20261119-145300 (`--seed basic`, executable `852d92879030…`)

| Area | Checks | Result |
| --- | --- | --- |
| History | Opens on yesterday `1 of 2 tasks complete`; three-days-ago day row; Completed filter keeps progress; previous/this month; Unfinished lists both days, newest first, `Back to History`; `db.txt` unchanged by browsing | Pass |
| Today | Add `Book flights` in Work with Return (`1/5`, stored day, order 4, Work); Escape discards a draft; complete (`2/5`); edit keeps rowid 8; delete returns `1/4`; Command-2, Command-1, Command-N | Pass |
| Later | `2 tasks remaining`; View > Later; add `Renew passport`; Move to Today with `Moved task to Today.`, status `1/5`, stored as today's last row in General | Pass |
| Categories | Create Health; rename Errands to Shopping (group header follows); Move to Shopping on a row; collapse General saved in defaults and kept after relaunch | Pass |
| Menu bar | Count `1/4` and label; a status-item press from Later opens Today; the glance lists the three unfinished rows, `Later · 2 remaining`, Open Today, Add Task…, Settings…, Quit, and Add Task… opens Today's composer. The first glance request found no menu (the documented background-menu gotcha); the immediate retry passed | Pass |
| Settings | Open in the same window; Command-comma opens no second window; Dark saved and kept after relaunch; Quick Add on registers the fake hotkey and off ignores it | Pass |
| Quick Add panel | The panel saved and discarded and kept the `Half typed` Today draft, but its text arrived mixed: the field already held `ar` when focused and the row saved as `aQick added task`; a second attempt showed the panel only after the 10 s wait and saved `ded task`. Keystrokes typed on the shared Mac reach a key Quick Add panel, and no Quick Add source changed since before the Calendar work (`6cdccb0`), so this is recorded as inconclusive rather than as a Calendar regression | Inconclusive |
| Persistence | `db.txt` and `preferences.json` identical in the changed, stopped and relaunched snapshots | Pass |

### Requirement status

| Requirement | Status | Evidence and limits |
| --- | --- | --- |
| REQ-001 Sidebar entry and route | Pass | Run 145100 |
| REQ-002 Views and navigation | Pass | Run 145100 |
| REQ-003 Create, edit, delete | Pass | Run 145100 editor checks |
| REQ-004 Time grid | Pass, partial | Placement, overlaps, today marker, current-time line observed; midnight rollover not observed |
| REQ-005 Persistence | Pass | Relaunch in runs 145100, 145207 and 145300; v5 copy upgrade |
| REQ-006 Drags | Partial | Draw and resize were user-observed during TASK-011 (runs 20261118-205440 to 20261119-012007); moving by drag has never been observed in the running app; the keyboard alternative passed; planners covered by hosted tests |
| REQ-007 Month | Pass, partial | Lines, `+N more` at 100%, 150% and the minimum window, opening a day; keyboard focus and arrows on cells not observed |
| REQ-008 Saved-only changes and failures | Pass, partial | Simulated read and write failures; the delete-failure message not observed |
| REQ-009 Keyboard, buttons, accessibility | Partial | Identifiers, spoken labels, button paths and Return/Escape on blocks pass; Tab focus on blocks and VoiceOver not observed |
| REQ-010 Documentation | Pass | This record and #94 |

### Still not tested

- Pointer gestures in the running app: slot click, drawing, resizing, moving, Escape during a drag, auto-scroll, and a failed drag save. The harness cannot post them and the user declined manual checks in this session.
- The compact rail (below 740 × 480 pt): the window minimum keeps the layout at least 800 × 560 pt at every zoom, so it could not be reached.
- VoiceOver; Tab focus on blocks; keyboard focus and arrows on Month cells.
- macOS 14 (including its resize cursor) and Xcode 16.4 locally; CI covers the Xcode 16.4 build and tests only.
- Midnight rollover in the running app; the delete-failure message; the `This block no longer exists.` path.
- A production-identity app, App Sandbox paths, and the first upgrade of the user's real database.
- A clean Quick Add panel text entry (see the inconclusive row above).

Calendar acceptance is partial: every drivable Calendar check passes and no regression was found in Today, Later, History, Categories, the menu bar or Settings, but the gestures and system cases above remain open.

### Before upgrading real data

The installed `/Applications/MenuPocket.app` (executable `169a8cd2…`, running throughout) predates v6 and was not touched. Opening the real database with any v6 build is one-way. Before doing it, quit every MenuPocket copy, back up `notes.sqlite` as in [Schema v6 upgrade preparation](WORKFLOW.md#schema-v6-upgrade-preparation), and decide whether to accept the open gaps above, in particular moving blocks by drag, which has not been seen working.

## Cleanup

Every fixture run ends with its own `cleanup.txt`, which trashes and unregisters its temporary `MenuPocketVerify.app`. The card handoffs record trashing and unregistering the Debug test host after their hosted runs. No card or run reports opening the user's main app or saved database.

TASK-015 used a separate `build/acceptance-015-DerivedData` so the user's `build/DerivedData` Debug app was not rebuilt. After the session its Debug test host and Release app were trashed and unregistered and the folder removed; the four fixture runs (144949, 145100, 145207, 145300) were cleaned with `fixture.sh cleanup` without warnings; the temporary v5 worktree was removed. Afterwards no fixture or test-host process remained, `/Applications/MenuPocket.app` had the same executable hash and PID, and the `build/DerivedData` Debug app was unchanged.

## Calendar title reopen regression — 2026-11-19

SQLite schema validation now reads Calendar text with the same byte-counted UTF-8 decoder as block queries. A v6 store with a previously saved title containing `U+0000` can reopen with the original title intact. The change requires no migration or data rewrite.

- **Automated — Pass.** The shared `MenuPocket` scheme passed 279 focused tests and all 617 tests with native Undo run separately, on macOS 26.6.2 with Xcode 27.0. The regression reopens a file with NUL at the start, middle and end of saved titles and compares the file bytes. A separate malformed-row case rejects a line break after NUL.
- **Native fixture — Pass.** In agent-operated run `20261119-171213`, the Calendar editor saved a title beginning with NUL via an Accessibility text setter. After a full quit and relaunch, the status item showed `1/4`, Today and Later listed the seeded tasks, and Calendar showed the same block. SQLite confirmed identical block ID, title bytes, day, and minutes, unchanged task, Later and category rows, `integrity_check = ok` and schema v6. Evidence is under `build/verify-menupocket/evidence/20261119-171213/`.
- **Installed app and personal database — Not tested.** This regression used the isolated fixture and XCTest stores.

## Calendar navigation while editing — 2026-11-19

- **Native fixture — Pass.** Agent-operated run `20261119-223957` reproduced the original sequence with Pairing open. Accessibility presses on Previous, Today, Next and the Month segment left Week 47 and the editor open. Escape restored focus to Pairing, confirmed by Return reopening it. The period controls worked after dismissal. A Month cell stayed disabled with New block open and opened Day after Cancel. SQLite snapshots before and after matched. Evidence is under `build/verify-menupocket/evidence/20261119-223957/`.
- **Automated — Pass.** The shared `MenuPocket` scheme passed 279 focused tests and all 617 tests with native Undo run separately, on macOS 26.6.2 with Xcode 27.0.
- **Physical outside click and VoiceOver — Not tested.** The native sequence used Accessibility presses and fixture-targeted Escape and Return.

## Focus after saving a block outside the period — 2026-11-19

The editor's Day stepper can move a block to a day outside the visible period. The save reloads the period without that block, so focus used to return to a block view that no longer existed. `ScheduleFocusTarget.afterEditor` now takes the blocks on the reloaded grid and sends focus to New block when the target block is not among them. Saves inside the period still return focus to the block.

- **Automated — Pass.** The shared `MenuPocket` scheme passed all 617 tests except the native Undo test, on macOS 26.6.2 with Xcode 27.0, in a separate `build/nav-focus-DerivedData` (log `build/nav-focus-tests.log`, result `build/nav-focus-tests.xcresult`). `testFocusGoesToNewBlockWhenTheSavedBlockLeftThePeriod` covers an edited block and a slot-click block saved outside the period. The native Undo test was not run separately for this change.
- **Native fixture — Pass.** In agent-operated run `20261119-225419` (`--seed calendar`), in Week 47, Pairing moved five days with Next day and saved as `Pairing|2026-11-23|630|690` with the same ID. The heading stayed on Week 47, Pairing left the grid, `id=scheduleNewBlock` was `[focused]`, and Return opened the New block editor. In Day view on Wednesday, Lunch moved one day and saved as `Lunch|2026-11-19|720|780`, with New block `[focused]`. Focus moved inside the day to 13:30 and saved. New block was not focused, and Return reopened Focus with Delete. Only those three rows changed between the first and last snapshots. Evidence is under `build/verify-menupocket/evidence/20261119-225419/`.
- **Cleanup.** The fixture was stopped and cleaned without warnings. The temporary Debug test host was trashed and unregistered, and `build/nav-focus-DerivedData` was removed. `/Applications/MenuPocket.app` kept PID 69490.
- **VoiceOver focus announcement — Not tested.**
