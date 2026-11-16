---
name: verify-menupocket
description: Launch and drive the real MenuPocket macOS interface (the Today/Later task window, History, category manager, menu bar count and right-click glance, Settings, and the Quick Add panel) on an isolated fixture build, then capture evidence from the Accessibility tree, screenshots, the SQLite rows, and the defaults. Use this after changing anything a MenuPocket user can see or whose saved data it changes, or when asked to verify, test, check, or demo MenuPocket behavior in the running app.
---

# Verify MenuPocket

MenuPocket is a native macOS app: SwiftUI views hosted in AppKit windows, plus a menu bar status item. It has no web, CLI, or API surface, so verification means driving the running app. Hosted XCTest (`xcodebuild … test`) covers logic but does not prove that menus, windows, or Settings respond (see `AGENTS.md`).

The harness lives in `.agents/skills/verify-menupocket/scripts/`:

- `fixture.sh` builds a **fixture app** from the working tree's `MenuPocket/**/*.swift`, with `FixtureMain.swift` replacing `MenuPocketApp.swift`. The fixture runs the production `AppDelegate`, `DailyNotesState`, views, status item, glance, and Quick Add panel. It writes to its own SQLite file and defaults suite, and uses fake login-item and hotkey services.
- `mpax` is a small Accessibility driver compiled from `mpax.swift`. It finds elements by AXIdentifier or label, presses them, types and sends keys to the fixture's PID only, and takes screenshots.

Every command below is run from the repository root.

## Before you start

- **Requirements:** macOS 14+, Xcode command-line tools (`xcrun swiftc`, `actool`), `sqlite3`, and `/usr/bin/python3`.
- **Permissions:** the app that runs your shell (the terminal or the agent app) needs Accessibility, for driving, and Screen Recording, for screenshots. `mpax` exits with code 77 when Accessibility is missing. Do not trigger a permission prompt. Tell the user what to grant and report the change as unverified.
- **Screen etiquette:** this runs on the user's real screen. On launch the fixture opens its window, takes focus once, and adds a second count to the menu bar. **Ask the user before launching** if someone may be using the Mac, and never loop launches. After launch, `mpax` acts through Accessibility and posts key events to the fixture's PID only. That works while the fixture is in the background and never types into another app.
- **Where it can't run:** this needs a logged-in macOS GUI session. Cloud agents, CI, and SSH sessions without one can't run it. In those cases, report the change as unverified and say why.
- **Isolation:** each run gets bundle ID `local.menupocket.verify.r<run>`, database `build/verify-menupocket/runs/<run>/data/fixture.sqlite`, and defaults suite `local.menupocket.verify.r<run>.defaults`. Runs can coexist. Only drive the run you built. Never drive or quit `/Applications/MenuPocket.app` or any other session's run, and never read or write the user's `local.menupocket.app` container.
- **What a fixture cannot prove:** the fixture is unsandboxed and has a different bundle ID. App Sandbox paths, the real `SMAppService` login item, the real Carbon Control-Option-N hotkey, Dock/login launch, and the upgrade of the user's real database are therefore outside it. Report those as Not tested unless they were checked another way.

## Launch

```bash
.agents/skills/verify-menupocket/scripts/fixture.sh build
```

This takes about 40 s and needs no UI. It compiles the fixture and `mpax` into `build/verify-menupocket/runs/<run>/`, writes `evidence/<run>/identity.json` (source revision, dirty app sources, hashes, bundle ID, database, defaults suite), and prints `RUN=<run>`. Pass that ID to every later command. A compile failure means the working tree does not compile. Fix it before verifying. Rebuild after every source change, because evidence from an older build is stale.

```bash
.agents/skills/verify-menupocket/scripts/fixture.sh launch <run> --seed basic
```

Launch is ready when it prints `Ready: PID <pid>, status item: … title="1/4" …`. It waits for the status item and for the task window's `id=todayTab`. A status title of `—` means storage could not be read. The first launch of a fresh build can take up to a minute while macOS assesses the newly signed bundle; later launches take a few seconds. If launch times out, run `doctor` instead of launching again. `doctor` finds and adopts a fixture that started late, and `launch` refuses to start a second instance of the same run.

- **`--seed empty`** (the default) gives a fresh schema-v6 store created by the production migrations: Today shows `0/0` and an empty state.
- **`--seed basic`** adds categories `Work` and `Errands`. Today has `Review pull request` (Work), `Write release notes` (Work, completed), `Buy coffee beans` (Errands), and `Water the plants` (General). Yesterday has `Call the dentist` (unfinished) and `Send weekly report` (completed). Three days ago has `Renew library books` (unfinished). Later has `Plan the team offsite` (Work) and `Read the SQLite docs` (General).
- **Seeding** happens only when the run's database does not exist yet. Relaunching the same run keeps every change, which is how persistence is checked.
- **`--now 2026-10-08T16:00:00Z --tz America/Toronto`** fixes the clock for date-sensitive checks. Without it the fixture uses the real clock.

To stop the fixture the way Command-Q would, so `applicationWillTerminate` runs, use `fixture.sh stop <run>`. Full teardown is under [Cleanup](#cleanup).

## Doctor

```bash
.agents/skills/verify-menupocket/scripts/fixture.sh doctor <run>
```

This is a read-only check, and the first thing to run whenever anything looks off. It checks that:

- the bundle exists and its executable matches the hash in `identity.json`;
- a process is running this run's executable (from the pid file, or found by the run's unique executable path and then recorded);
- `lsof` shows the run's `fixture.sqlite` open and nothing from `Containers/local.menupocket.app`;
- Accessibility works, and the status item and task window are visible to it.

It also lists other MenuPocket processes, for information only. Exit code 1 means at least one `FAIL` line. Don't drive the instance until that is fixed or relaunched.

## Drive

`fixture.sh ax <run> <command> [args]` runs `mpax` against the run's PID and appends the action and its first output line to `evidence/<run>/actions.log`.

| Command | Effect |
| --- | --- |
| `tree [depth]` | Print the status item, every window, sheet, and open menu as an indented AX tree. |
| `find <query>` | List every match once (no waiting). Exit code 2 when nothing matches. |
| `value <query>` | Print one element's role, label, value, identifier, and state. Waits up to 3 s. |
| `frame <query>` | Print one element's screen frame in points (`frame x=… y=… w=… h=…`). |
| `press <query>` | `AXPress` the element: buttons, checkboxes, segments, menu items, pop-ups, and the status item (a primary click). |
| `action <query> <name>` | Perform a named action, such as `action status-item "Show quick look"` (the right-click glance). `actions <query>` lists names. |
| `focus <query>` / `type <text>` / `key <combo>` | Focus a field, type Unicode text, or send `return`, `escape`, `tab`, `space`, `up`/`down`/`left`/`right`, `cmd+n`, `cmd+1`, `cmd+2`, `cmd+comma`, `cmd+equal`, `cmd+shift+equal`, `cmd+minus`, `cmd+0`, `cmd+w`, `cmd+q`, `cmd+a`/`c`/`v`/`x`/`z`. |
| `wait <query> [s]` / `gone <query> [s]` | Wait (default 10 s) for an element to appear or disappear. |
| `menu-path <top> <item>…` | Choose from the main menu bar, for example `menu-path View Later`. Exit code 4 if the item is disabled. |
| `screenshot <file.png> [query]` | Capture the frontmost fixture window, a window matched by query (captured by window ID), or any element's screen rectangle (menus, the glance, the status item). |
| `windows` / `activate` | List the fixture's windows, or bring the fixture to the front. Activating is rarely needed. |

**Queries** are comma-separated terms that must all match: `id=X` (AXIdentifier), `id^=X` (identifier prefix), `label=X` (exact title, description, or value), `label~=X` (case-insensitive substring), `role=AXButton`, `subrole=AXCloseButton`, and `status-item`. Write a literal comma in a value as `\,` (group headers are labeled like `Work\, 1 of 2 complete`). An unknown term is an error (exit 64). Add `#N` to pick the Nth match. Prefer `id=`. SwiftUI menu items have generic identifiers, so match them with `role=AXMenuItem,label=<title>`. The row `…` actions and the composer Category control open Daybook popovers, not menus: their items are buttons with `id=taskAction-<action>` and `id=categoryOption-<general|category UUID>` (see the [Today recipe](features/today-tasks.md)). Task UUIDs change on every run, so reach rows through their visible text, for example `label=Actions for task: Buy coffee beans` or `role=AXCheckBox,label=Buy coffee beans`.

Stable handles in the task window: `todayTab`, `laterTab`, `taskDestination`, `addTask`, `manageCategories`, `taskHistoryEntry`, `yesterdayHistoryEntry`, `todayProgress`, `laterRemainingCount`, `todayTaskList`/`laterTaskList`, `newTaskDraft`/`newLaterTaskDraft`, `newTaskCategory`/`newLaterTaskCategory`, `saveTask`/`saveLaterTask`, `cancelNewTask`, `editTaskDraft`, `cancelTaskEdit`, `taskDeletionConfirmation`, `confirmTaskDeletion`, `cancelTaskDeletion`, `todayEmptyState`, `todayUnavailableState`, `retryTodayTasks`, and `laterMoveNotice`. Group headers are `taskGroup-general` or `taskGroup-<category UUID>`, and their value is `Expanded`/`Collapsed`. The Settings window opens from `label=Open Settings`. The [feature map](features/README.md) has the handles for each feature.

Recipes:

```bash
F=.agents/skills/verify-menupocket/scripts/fixture.sh
$F ax <run> press id=addTask                                        # open the composer
$F ax <run> type "Book flights"                                     # the new field has focus
$F ax <run> press id=newTaskCategory                                # open the Category popover
$F ax <run> press "id^=categoryOption-,label=Work"                  # choose Work
$F ax <run> focus id=newTaskDraft && $F ax <run> key return         # save with Return
$F ax <run> press "label=Actions for task: Book flights"            # open the row "…" popover
$F ax <run> press id=taskAction-delete                              # Delete…, then id=confirmTaskDeletion
$F ax <run> press status-item                                       # primary click on the count
$F ax <run> action status-item "Show quick look"                    # right-click glance
```

Simulated system boundaries, each logged to `actions.log`:

- `fixture.sh quickadd <run>` presses the fake Control-Option-N hotkey (SIGUSR1). It does nothing unless Quick Add is on in Settings.
- `fixture.sh next-day <run>` advances the fixture clock one day and posts a day change (SIGUSR2).
- `fixture.sh fail-open <run> on|off` makes the next storage open throw. Turn it on, then `stop` and `launch` to see Unavailable. Turn it off and press `id=retryTodayTasks` to recover.

Driving gotchas:

- **Menus:** a menu opened by `press` closes when the fixture app deactivates, for example when the user clicks another app. Open a menu and press its item in back-to-back calls. If the item then reports `no element matches`, reopen the menu once and retry.
- **Reopening menus:** after `key escape` closes a menu, run `gone role=AXMenu` before opening another. A menu press sent while the previous menu is still closing is swallowed.
- **Waiting:** `find` does not wait, while `press` and `value` retry for 3 s. After an action that changes the view, use `wait`/`gone` instead of `sleep`. Values can lag the action: a control keeps showing its old choice for a moment, so assert with `wait "id=newTaskCategory,label=Work"`, not an immediate `value`.
- **Closing windows:** key events reach the fixture's key window, which may not be the window you want while the fixture is in the background. To close a specific window, press its close button (`press subrole=AXCloseButton`, adding `#N` when several windows are open), or `activate` first and then send `key cmd+w`.
- **Disabled controls:** `AXPress` on a disabled control returns without acting. Read `value <query>` first when enablement is part of the check (look for `[disabled]`).
- **Drags:** drag and drop (task reordering by the six-dot handle, category drags in the manager) cannot be driven with this harness. Use the keyboard path (row popover `Move Up`/`Move Down`/`Move To`) and report pointer drags as Not tested, or give the user exact manual steps. `docs/WORKFLOW.md` explains why synthetic drags are inconclusive.
- **Screenshots:** an element screenshot is a screen rectangle, so whatever overlaps it is captured too. A window screenshot (no query, or a `role=AXWindow` query) is captured by window ID. Menu bar items hidden behind the notch still work through Accessibility but may not show in a screenshot.

## Evidence

Evidence goes to `build/verify-menupocket/evidence/<run>/`. It is ignored by Git and survives cleanup.

- `identity.json` records which source and binary were verified.
- `actions.log` has every `ax`, signal, `fail-open`, launch, and stop, with its result.
- `snapshots/NN-<label>/` holds `db.txt` (schema version, categories, every task with its rowid, day, `display_order`, completion, and category, plus Later rows), `defaults.plist`, `preferences.json` (decoded `AppPreferences`), `ax-tree.txt`, and `window.png`. Create one with `fixture.sh snapshot <run> <label>`.
- `fixture.log`, `build.log`, and `cleanup.txt` are copied in at stop or cleanup.

Proof standards:

- **Use the user path.** Drive buttons, menus, keys, and the status item through `mpax`. Never write SQLite or defaults to produce a state. The only exception is the `--seed` preconditions, and the report must name them.
- **Capture the action and the result.** Take a snapshot before and after. The proof is the change in the AX tree or screenshot, the status item count, and the database rows and defaults, together with the matching `actions.log` lines.
- **Check side effects.** A visible row is not enough: confirm the row in `db.txt` (day, order, category, completion) and the decoded preference in `preferences.json`.
- **Persistence:** `stop`, then `snapshot` (the fixture is not running, so this records stored state), then `launch` the same run without reseeding, then `snapshot` again. Compare the two `db.txt` files and the visible result.
- **Fakes stay at existing boundaries.** The login item, Carbon hotkey, day changes, and storage-open failure are simulated. Say so, and do not claim the real system integration from them.
- **Reporting:** report each check as Pass, Fail, Not tested, or Blocked, and say that it was agent-operated on a fixture. When the work is recorded in the project's acceptance docs, follow `docs/WORKFLOW.md`, which keeps user-operated and agent-operated observations apart.

## Cleanup

```bash
.agents/skills/verify-menupocket/scripts/fixture.sh cleanup <run>
```

Run this after every session, including failed attempts. Cleanup:

1. Quits the run's own PID, falling back to `kill -9` of that PID only. It never kills by name.
2. Copies the logs into the evidence directory.
3. Moves the bundle to the Trash, as required by `docs/WORKFLOW.md#test-artifact-cleanup`.
4. Unregisters from LaunchServices every path recorded under the run's unique bundle ID, including the Trash copy, re-checking for a few seconds because macOS registers the Trash copy again right after the move. It also unregisters Trash copies left by earlier verify runs, which macOS can re-register minutes later.
5. Deletes the run's defaults suite and domain and any saved application state.
6. Removes `build/verify-menupocket/runs/<run>`.
7. Writes `cleanup.txt` with its checks: the bundle path is gone, LaunchServices has no path, the defaults are removed, and no process is left.

Afterwards, confirm the evidence remains with `ls build/verify-menupocket/evidence/<run>`. A `WARN` line in `cleanup.txt` means a path was still registered when the check ran. Unregister it with `lsregister -u "<path>"` and say so in the report. Cleanup never touches `/Applications/MenuPocket.app`, the `local.menupocket.app` container, other Trash contents, or another run's bundle, data, or process. For other runs, it only unregisters copies already in the Trash.

If a run's directory was deleted by hand, `cleanup` reports that nothing is left, but its LaunchServices entries and defaults suite can linger. Remove them by that run's bundle ID: run `lsregister -u <path>` for each `path:` that `lsregister -dump` lists under `identifier: local.menupocket.verify.r<run>` (`lsregister` is in `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/`), then `defaults delete local.menupocket.verify.r<run>.defaults`.

## Helpers

- `scripts/fixture.sh` runs `build`, `launch`, `doctor`, `ax`, `snapshot`, `quickadd`, `next-day`, `fail-open`, `stop`, and `cleanup`, as shown above. It finds the repository with `git rev-parse` from its own location, so it works from any directory and through the `.claude/skills` link.
- `scripts/FixtureMain.swift` is the fixture's entry point: launch options, the `basic` seed, fake services, and the signal handlers. When `AppDelegate`, `AppModel`, or `DailyNotesState` initializers change, `build` fails here; update this file in the same change. Add new seeds here as named `--seed` values.
- `scripts/mpax.swift` is the Accessibility driver, compiled per run into `runs/<run>/bin/mpax`. `mpax trash <path>` is used by cleanup.
- The [feature map](features/README.md) has the recipes for each feature. Update it in the same change as the feature.
