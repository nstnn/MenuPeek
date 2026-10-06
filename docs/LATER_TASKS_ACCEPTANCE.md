# Later tasks actual-interface acceptance

## 2026-10-06 — TASK-011 isolated native fixture

**Status: Pass, user-reported, scoped to the isolated fixture.** The user ran the checks by hand on the fixture (PID 37671) and reported all 16 as passing. Automated evidence is in [LATER_TASKS_REGRESSION.md](LATER_TASKS_REGRESSION.md). Production-identity and system checks below remain Not tested.

Agent-side cross-check: the fixture's launch counter, exit snapshot (`snapshot-L1-02.json`) and SQLite contents show one launch, no day offset, the *Work* category still present and no bulk Later rows. That is consistent with A4 (one moved task, no duplicate; integrity `ok`, schema v3), but the retained data does not record A11, A12, B1, B2 or B3. Those results rest on the user's report; the user confirmed them when asked.

### Method

Per the project's verification agreement, the user performs the interface checks by hand; the agent does not control or record the screen. The agent builds the fixture, records identity, reads fixture snapshots and SQLite contents, and cleans up afterwards.

The fixture runs the production `AppDelegate`, task window, status item, Quick Add panel, Settings and `DailyNotesState` with:

- isolated SQLite `build/task011/native/notes.sqlite` (seeded only when it has no categories, so relaunch does not reseed);
- isolated defaults suite `local.menupocket.task011.fixture.defaults`;
- injected clock with a persisted day offset; **Fixture › Advance Day** posts `NSCalendarDayChanged` on the state's injected notification center;
- fake login service (no registration) and fake hotkey service (**Fixture › Simulate Quick Add Hotkey** stands in for the global shortcut);
- a repository wrapper whose Fixture menu toggles write failures and Today/Later read failures.

It cannot establish production-identity, sandbox, real global-hotkey, login-item or real-data-upgrade behavior.

### Artifact identity

| Item | Value |
| --- | --- |
| Source | `feat/later-tasks` at `85dd03b2ed8e4d25e2eeae9d14fe3422f385affe`, clean tracked tree |
| App source digest | `00769e7fe6ea5969598832fbe69f58c2718319cb7aedeb42dec7ee0c553d5e52` (SHA-256 of sorted per-file SHA-256 list of `MenuPocket/**/*.swift`) |
| Fixture source | `build/task011/native/Fixture.swift`, SHA-256 `a7acb2379149a474fd419f3c54e4a6a0ea85ce00d2454b54819ee2ef25ab885a` |
| Bundle | `build/task011/native/MenuPocketTask011Fixture.app`, ID `local.menupocket.task011.fixture`, ad hoc signed |
| Executable SHA-256 | `f0ab76e87aab08c5d6d7616674a79164a5b327a6780dc0b74ae9ab317b05fa77` |
| Build | `swiftc -swift-version 6 -parse-as-library -g -Onone -target arm64-apple-macos14.0`, all app sources except `MenuPocketApp.swift`, plus the fixture; Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 26.6.2 |
| Smoke launch | PID 33475 started on Today, status `1/2`, Later 4 remaining; quit and exited. Its data moved to `build/task011/native/smoke/` and the defaults domain was deleted so the user's run starts from a fresh seed. |
| Main-app baseline | `build/task011/preservation-before.json` (9 files) |

### Seed

Today: *Today seed task* (Work, open) and *Today collision seed* (General, done) → status `1/2`.
Later: *Move this task* (Work), *Move failure collision* (Work, shares the Today row's UUID so moving it must fail), *Completed Later task* (Completed only, done), a long wrapping task (long category name), *General Later seed* (General) → 4 remaining.

### Checks

Results as reported by the user on 2026-10-06.

| ID | Check | Expected | Result |
| --- | --- | --- | --- |
| A1 | First launch | Window opens on **Today**; `Today | Later` control visible; status item `1/2`. Later shows "4 tasks remaining", groups Work · Completed only · long category · General with per-group "N remaining"; no date or progress bar in Later. | Pass (user-reported) |
| A2 | Size and appearance | At Fixture › Minimum Size and Normal Size, in Settings › Appearance Light and Dark, both tabs: long text/name wraps, tab control, Add, Categories and Settings stay usable. | Pass (user-reported) |
| A3 | Later add/complete/edit/delete | ⌘N in Later adds to Later with the chosen category. Checkbox mutes the row in place and changes the count; edit Save keeps position; Escape cancels; empty text is rejected; Delete… › Cancel keeps, Delete removes. | Pass (user-reported) |
| A4 | Move to Today | *Move this task* › Move to Today: row leaves Later, "Moved task to Today." appears, Later stays selected, count −1; Today shows it once under Work; status total +1. Completed rows offer no Move to Today. | Pass (user-reported) |
| A5 | Move failure | *Move failure collision* › Move to Today: error shown, row stays in Later, Today and status unchanged. | Pass (user-reported) |
| A6 | Write failure recovery | Fixture › Fail Writes, add in Later: error, typed text kept. Fixture › Recover All, save again: saved once. | Pass (user-reported) |
| A7 | Drafts and guards | Unsaved Today and Later drafts survive tab switches and ⌘W + Show Tasks/Dock (window reopens on the same tab). Inline edit, delete confirmation and Categories sheet each block tab switching until resolved. | Pass (user-reported) |
| A8 | Status item click | Later selected, nothing open: click status item → Today. Later inline edit open: click → window comes forward, stays on Later, edit kept. | Pass (user-reported) |
| A9 | Command-N routing | ⌘N opens the composer of the selected tab only. | Pass (user-reported) |
| A10 | Quick Add while Later selected | Simulate Quick Add Hotkey, save a task: it lands in Today/General, status total +1, Later stays selected, both drafts and Later count unchanged. | Pass (user-reported) |
| A11 | Day change during Later edit | Start a Later edit, Fixture › Advance Day: edit stays open with typed text and saves; Later rows unchanged and undated; Today shows the new (empty) day. | Pass (user-reported) |
| A12 | Shared categories | Rename a category: new name in both tabs. Remove *Work*: confirmation counts tasks across Today and Later; after removal those tasks remain, under General, in both tabs. | Pass (user-reported) |
| A13 | Keyboard and focus | Tab reaches tab control, Add, Categories, Settings and row actions; Return saves and Escape cancels the composer; after a move, focus lands on a surviving row/group or Add. | Pass (user-reported) |
| B1 | Quit and relaunch | After ⌘Q the process exits; relaunch opens on **Today**; Later rows, completion, edits, categories and moved task match pre-quit state, nothing duplicated or reseeded. | Pass (user-reported) |
| B2 | Large/empty/completed lists | Add 40 Later Rows: list scrolls, moving a bottom row shows the notice. Complete All Later: groups stay with 0 remaining, rows muted. Empty Later: empty state, also at minimum size. | Pass (user-reported) |
| B3 | Read failure isolation | Fail Later Read: Later shows unavailable + Retry, Today still shows its tasks and status. Recover All restores Later. | Pass (user-reported) |

### Not covered by this fixture

Production-identity status item, genuine Dock reopen of the signed app, real global Quick Add shortcut, quiet login launch, App Sandbox behavior, VoiceOver journey, and real-data v2→v3 upgrade remain Not tested.

### Cleanup

Done 2026-10-06. Fixture quit via Apple Event; no process remained. The bundle's original path was unregistered from LaunchServices, moved with `FileManager.trashItem` to `~/.Trash/MenuPocketTask011Fixture.app`, and the Trash path was unregistered. LaunchServices and Spotlight show no entries for the fixture; the defaults domain `local.menupocket.task011.fixture.defaults` was deleted. All nine main-app/data baseline hashes matched (`build/task011/preservation-before.json` vs `preservation-after.json`). The fixture database, snapshots and source are retained under ignored `build/task011/`.
