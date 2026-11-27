# Later list

The Later tab holds undated tasks with only text and an optional category. Its main pane shows `N tasks remaining` and groups undated tasks by category. The persistent left rail retains today’s date, explicitly labeled Today progress, Calendar, History, Categories and Settings at the same positions as Today. An unfinished Later task can be moved to Today, and an unfinished Today task can be moved to Later (see [Today tasks](today-tasks.md)). Later-only changes never change the menu bar count; Move to Today raises Today's total by one.

## Sub-features

- `later-switch` selects Later from the Daybook rail (also available while History, Categories, or Settings is shown), Command-2, or View > Later, and returns with Command-1.
- `later-add` adds a Later task with its own draft and category choice.
- `later-complete-edit-delete` works as in Today, inside Later.
- `later-move-today` moves an unfinished task to the end of Today, keeps its text and category, and shows `Moved task to Today.`
- `later-count-isolation` keeps the menu bar count unchanged for Later-only writes.
- `later-recovery` shows `id=laterRecoveryNotice` when a Later edit loses its task or category, with its own `id=dismissLaterRecoveryNotice` button that clears only Later's notice.

## How to get to it (user POV)

- Click `Later` in the rail's `Today | Later` control, or press Command-2.
- Choose View > Later from the menu bar.
- Use the row `…` popover for Move to Today, Edit, and Delete….

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`. Later holds `Plan the team offsite` (Work) and `Read the SQLite docs` (General), and the status item reads `1/4`.
- `$F snapshot <run> before` has been taken.

- **Switch to Later.** Run `$F ax <run> press id=laterTab` and `$F ax <run> wait id=laterTaskList`. The heading reads `Later`, and `value id=laterRemainingCount` reads `2 tasks remaining`. The shared rail still exposes `daybookDate`, `todayProgress` (`1 of 4 complete`) and `taskHistoryEntry`. Group headers are `id=laterTaskGroup-general` and `id^=laterTaskGroup-`, labeled `<name>, N remaining` (for example `Work, 1 remaining`) rather than Today's `completed of total`.
- **Menu route.** Run `$F ax <run> press id=todayTab`, then `$F ax <run> menu-path View Later`. `laterTab` has value `1` again.
- **Add.** Run `$F ax <run> press id=addTask`, `$F ax <run> wait id=newLaterTaskDraft`, `$F ax <run> type "Renew passport"`, `$F ax <run> focus id=newLaterTaskDraft`, and `$F ax <run> key return`. The count reads `3 tasks remaining`, and the status item still reads `1/4`. In the snapshot, `Renew passport` is a new `later_tasks` row.
- **Move to Today.** Run `$F ax <run> press "label=Actions for task: Read the SQLite docs"`, then `$F ax <run> press id=taskAction-moveToToday`. `value id=laterMoveNotice` reads `Moved task to Today.` (read it at once: it hides after 5 s), Later shows one fewer remaining, the status item reads `1/5`, and the tab stays on Later.
- **Stored move.** Run `$F snapshot <run> after-move`. In `db.txt`, `Read the SQLite docs` is no longer a `later_tasks` row and is a `notes` row with today's `day_key`, the day's highest `display_order`, `done` 0, and category `General`.
- **Completed task cannot move.** Complete a Later task with `$F ax <run> press "role=AXCheckBox,label=Plan the team offsite"`, then open its `…` popover. `find id^=taskAction-` lists only `taskAction-edit` and `taskAction-delete`. Close the popover with `$F ax <run> key escape` and `$F ax <run> gone id=taskActionsPopover`.
- **Proof.** Run `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/later.png` and `$F snapshot <run> later-final`.

## Gotchas

- Later rows have no drag handle and no Move Up or Move Down. Reordering Later is out of scope, so don't report it as a failure.
- The tab switch is refused while an edit, a deletion confirmation, a category rename or removal confirmation, or a Calendar block editor is open. `todayTab`/`laterTab` presses then do nothing. An idle Categories pane does not block it: the press closes the pane and switches.
- Each tab keeps its own draft (in memory only, never in defaults) and its own remembered category. Later's keys in `defaults.plist` are `local.menupocket.app.taskCategories.later.lastUsedCategoryID` (written only after a successful add with a custom category; absent for General) and `…later.collapsedGroupIDs`. Check the Later keys, not the Today ones.
- Later's recovery notice needs a lost edit target: the UI blocks category removal and day changes do not touch Later edits, so it appears only when a refresh no longer finds the edited row (for example after removing that `later_tasks` row from the run's own database while the fixture is stopped). Hosted tests cover its Dismiss behavior; record the native check as Not tested when it was not set up.
- After Move to Today, the moved row belongs to Today's group for its category. Look for it with `press id=todayTab`, not in Later.
