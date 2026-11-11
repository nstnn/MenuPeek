# Later list

The Later tab holds undated tasks with only text and an optional category. Its main pane shows `N tasks remaining` and groups undated tasks by category. The persistent left rail retains today’s date, explicitly labeled Today progress, History, Categories and Settings at the same positions as Today. An unfinished Later task can be moved once to Today. Later-only changes never change the menu bar count; Move to Today raises Today's total by one.

## Sub-features

- `later-switch` selects Later from the Daybook rail (or the title-bar control on History), Command-2, or View > Later, and returns with Command-1.
- `later-add` adds a Later task with its own draft and category choice.
- `later-complete-edit-delete` works as in Today, inside Later.
- `later-move-today` moves an unfinished task to the end of Today, keeps its text and category, and shows `Moved task to Today.`
- `later-count-isolation` keeps the menu bar count unchanged for Later-only writes.

## How to get to it (user POV)

- Click `Later` in the window's `Today | Later` control, or press Command-2.
- Choose View > Later from the menu bar.
- Use the row `…` menu for Move to Today, Edit, and Delete….

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`. Later holds `Plan the team offsite` (Work) and `Read the SQLite docs` (General), and the status item reads `1/4`.
- `$F snapshot <run> before` has been taken.

- **Switch to Later.** Run `$F ax <run> press id=laterTab` and `$F ax <run> wait id=laterTaskList`. The heading reads `Later`, and `value id=laterRemainingCount` reads `2 tasks remaining`. The shared rail still exposes `daybookDate`, `todayProgress` (`1 of 4 complete`) and `taskHistoryEntry`. Group headers are `id=laterTaskGroup-general` and `id^=laterTaskGroup-`.
- **Menu route.** Run `$F ax <run> press id=todayTab`, then `$F ax <run> menu-path View Later`. `laterTab` has value `1` again.
- **Add.** Run `$F ax <run> press id=addTask`, `$F ax <run> wait id=newLaterTaskDraft`, `$F ax <run> type "Renew passport"`, `$F ax <run> focus id=newLaterTaskDraft`, and `$F ax <run> key return`. The count reads `3 tasks remaining`, and the status item still reads `1/4`. In the snapshot, `Renew passport` is a new `later_tasks` row.
- **Move to Today.** Run `$F ax <run> press "label=Actions for task: Read the SQLite docs"`, then `$F ax <run> press id=taskAction-moveToToday`. `value id=laterMoveNotice` reads `Moved task to Today.`, Later shows one fewer remaining, the status item reads `1/5`, and the tab stays on Later.
- **Stored move.** Run `$F snapshot <run> after-move`. In `db.txt`, `Read the SQLite docs` is no longer a `later_tasks` row and is a `notes` row with today's `day_key`, the day's highest `display_order`, `done` 0, and category `General`.
- **Completed task cannot move.** Complete a Later task with `$F ax <run> press "role=AXCheckBox,label=Plan the team offsite"`, then open its `…` popover. `find id^=taskAction-` lists only `taskAction-edit` and `taskAction-delete`, and the button's help reads `Opens Edit and Delete actions`. Close the popover with `$F ax <run> key escape` and `$F ax <run> gone id=taskActionsPopover`.
- **Proof.** Run `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/later.png` and `$F snapshot <run> later-final`.

## Gotchas

- Later rows have no drag handle and no Move Up or Move Down. Reordering Later is out of scope, so don't report it as a failure.
- The tab switch is refused while an edit, deletion confirmation, or the category manager is open. `todayTab`/`laterTab` presses then do nothing.
- Each tab keeps its own draft and remembered category (`local.menupocket.app.taskCategories.later.*` in `defaults.plist`). Check the Later keys, not the Today ones.
- After Move to Today, the moved row belongs to Today's group for its category. Look for it with `press id=todayTab`, not in Later.
