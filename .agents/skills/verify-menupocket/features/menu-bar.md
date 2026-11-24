# Menu bar count and glance

MenuPocket keeps a status item in the macOS menu bar that shows Today's saved progress as `completed/total` (`0/0` for an empty day, `—` when tasks could not be read). A primary click restores the task window on Today. A right-click or Control-click opens a read-only quick look: the date, a progress bar and `N of M done`, up to five unfinished Today tasks, `Later · N remaining`, and Open Today, Add Task…, Settings…, and Quit MenuPocket. The quick look never changes a task.

## Sub-features

- `menubar-count` mirrors saved Today progress after every write, including Quick Add and Move to Today.
- `menubar-open-today` restores the window on Today, even when closed or on Later.
- `menubar-glance` shows the read-only quick look with correct rows and counts.
- `menubar-continued-rollback` shows No unfinished tasks, rather than All done, when a simulated backward date makes continued originals Today again; real completion/total remains unchanged.
- `menubar-glance-actions` covers Open Today; Add Task… (always to Today); Settings…; and Quit.
- `menubar-unavailable` shows `—`, then recovers through Retry in the window.
- `menubar-window-closed` keeps the count live with the window closed.

## How to get to it (user POV)

- Look at the count in the menu bar.
- Click it to open Today.
- Right-click or Control-click it for the quick look.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`, with the status item reading `1/4`.
- `$F snapshot <run> before` has been taken.

- **Read the count.** Run `$F ax <run> value status-item`. It shows `title="1/4" label="MenuPocket, today, 1 of 4 tasks completed"` and help text ending `Right-click for a quick look.`
- **Window closed, count live.** Close the task window with `$F ax <run> press subrole=AXCloseButton` (only the task window open) and `$F ax <run> gone id=todayTab`. Then `$F quickadd <run>` with Quick Add on (see [Settings and Quick Add](./settings-quick-add.md)), or `$F next-day <run>`. The status item value changes while no task window exists.
- **Click opens Today.** Select Later first (`press id=laterTab`) or close the window. Run `$F ax <run> press status-item` and `$F ax <run> wait id=todayTab`. `todayTab` has value `1`, and the window is back.
- **Open the quick look.** Run `$F ax <run> action status-item "Show quick look"` and `$F ax <run> wait role=AXMenuItem 5`. Then `$F ax <run> find role=AXMenuItem` lists the unfinished Today tasks, General first, titled `<text>\t<category>` when Today has more than one group and plain `<text>` otherwise (at most five, then `K more in Today`; a disabled `No tasks yet` on an empty day), `Later · 2 remaining`, `Open Today`, `Add Task…`, `Settings…`, and `Quit MenuPocket`. Capture it with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/glance.png role=AXMenu`. The image shows the date, the bar, and `1 of 4 done`.
- **Glance action.** Run `$F ax <run> press "role=AXMenuItem,label=Add Task…"`. The window opens on Today with `id=newTaskDraft` focused, even if Later was selected; the composer preselects the last category saved in Today. Add Task… is disabled while Today is unavailable or while an edit, a deletion confirmation, the Categories pane or a Calendar block editor is open. `$F ax <run> key escape` closes an open quick look and changes nothing. Run `gone role=AXMenu` before opening it again.
- **Read-only.** After opening and dismissing the quick look, a new snapshot's `db.txt` equals the previous one.
- **Unavailable and Retry.** Run `$F stop <run>`, `$F fail-open <run> on`, and `$F launch <run>`. The launch line shows `title="—"` and a label containing `unavailable`, and `find id=todayUnavailableState` matches. The quick look then shows a disabled `Tasks are unavailable.`, a `Retry` item, and a disabled `Add Task…`. `doctor` reports `FAIL  the run's fixture.sqlite is open` in this state by design. Run `$F fail-open <run> off` and `$F ax <run> press id=retryTodayTasks`. The status item returns to its saved count.
- **Proof.** Before and after snapshots, `actions.log`, and the glance screenshot together show the count, the action, and the unchanged rows.

## Gotchas

- `press status-item` is the primary click. The right-click glance is reached only with `action status-item "Show quick look"`, which is the same custom action VoiceOver uses. A physical Control-click and right-click are separate user paths; report them as Not tested unless a person performed them.
- The quick look opens asynchronously, so `find` straight after the action can miss it; always `wait role=AXMenuItem 5` first. Like other menus it closes when the fixture deactivates, so press its item in the next call; if that reports `no element matches`, reopen it once. The action occasionally opens nothing; if the wait times out, run `key escape` and `gone role=AXMenu`, then repeat the action once before reporting a failure.
- A crowded menu bar can hide the status item behind the notch. Accessibility still works, but a screenshot of `status-item` may be off-screen. Say so instead of retrying.
- The glance follows the macOS appearance, not the app's Theme setting, so a Dark theme with macOS in Light shows a light menu by design.
- The user's real MenuPocket shows its own count beside the fixture's. Always read `status-item` through this run's `ax`, never by screen position.
- `fail-open` only affects the next storage open. Set it before `launch`, not while the fixture is running.

### Continued originals after a backward date

On a fresh `basic` fixture first launched with `--now 2026-10-22T16:00:00Z --tz America/Toronto`, continue the unfinished Oct 21 dentist task through [History](history.md#continue-today-recipe). Stop and relaunch the same run with `--now 2026-10-21T16:00:00Z --tz America/Toronto` (no next-day offset for this recipe). This is an injected backward clock, never a change to the Mac's date. The saved original date is now Today with one real completion out of two, and no actionable unfinished task. Open the glance with `action status-item "Show quick look"`: header remains `1 of 2 done`, and the disabled body says `No unfinished tasks`, without `All done`. Snapshot both states and verify no rows changed during relaunch/browsing; dismiss with Escape and clean the run. Continued-only `0/1` and completed-plus-continued are also covered by model/menu tests.
