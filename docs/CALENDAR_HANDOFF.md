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

## Not tested

- Moving a block by dragging its body in the running app: the harness cannot post pointer drags and no manual run was recorded. The planners and save paths are covered by hosted tests.
- The 800 × 560 pt minimum window and the compact rail (no resize driver; 150% zoom is the closest check).
- VoiceOver; keyboard Tab focus on blocks; keyboard focus and arrow keys on Month cells (the driver's focus and key events did not reach them).
- The macOS 14 resize cursor, drags at zoom levels other than 100%, and macOS 14 in general.
- Light appearance for the editor popover and Month; the delete-failure message; the `This block no longer exists.` path in the interface.
- Midnight rollover of the current-time line and Today marker in the running app.
- A production-identity app and the first real-data v5→v6 upgrade.

Calendar acceptance is therefore partial. TASK-015 (integrated regression and native acceptance) is still to run and should confirm the open statements above.

## Cleanup

Every fixture run ends with its own `cleanup.txt`, which trashes and unregisters its temporary `MenuPocketVerify.app`. The card handoffs record trashing and unregistering the Debug test host after their hosted runs. No card or run reports opening the user's main app or saved database.
