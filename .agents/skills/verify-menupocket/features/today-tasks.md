# Today tasks

The Today tab of the task window lists the current local day's tasks in category groups, with a Daybook date rail, progress ring, and `N/M complete`. A user adds a task with text and a category, checks it off, edits its text or category, and deletes it after an inline confirmation. Each write is saved to SQLite at once and updates the menu bar count.

## Sub-features

- `daybook-layout` keeps the serif date rail, flat sections, row separators, and all controls usable in Light/Dark and at the 800 × 560 pt minimum. See [Daybook](daybook.md).
- `today-add` opens the composer, saves trimmed text with the chosen category, and appends the task to its group.
- `today-add-cancel` discards a draft with Escape or Cancel.
- `today-complete` toggles completion and updates progress and the menu bar count.
- `today-edit` changes a task's text and/or category in place.
- `today-delete` removes a task after inline confirmation; Cancel keeps it.
- `today-actions-popover` opens the row `…` as a Daybook popover (`id=taskActionsPopover`) below the button: Edit, Move Up, Move Down, a Move To list, and Delete… in red. Items are buttons `id=taskAction-edit`, `-moveUp`, `-moveDown`, `-moveTo-general`/`-moveTo-<category UUID>`, `-moveToToday` (Later), and `-delete`. Unavailable moves and the current group are `[disabled]`.
- `today-keyboard` routes Command-N (add), Command-1/Command-2 (tabs), and Command-W (close; the app keeps running).
- `today-persist` keeps saved tasks, order, and completion across quit and relaunch.

## How to get to it (user POV)

- Launch the app, which opens the task window on Today, or click the menu bar count.
- Choose `Add task` (`⌘N`) in the window, or File > Add Task.
- Use each row's checkbox, and its `…` popover for Edit, Move, and Delete….
- Press Command-1 from anywhere in the app to return to Today.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`, ready with status `1/4`.
- `$F doctor <run>` passes, and `$F snapshot <run> before` has been taken.

- **Open composer.** Choose Add task. Run `$F ax <run> press id=addTask` and `$F ax <run> wait id=newTaskDraft`. A focused `New task` field, an `id=newTaskCategory` pop-up showing `General`, and a disabled `id=saveTask` appear.
- **Enter text and category.** Type the text, then choose Work. Run `$F ax <run> type "Book flights"`, `$F ax <run> press id=newTaskCategory`, and `$F ax <run> press "role=AXMenuItem,label=Work"`. Then `$F ax <run> wait "id=newTaskCategory,label=Work" 3` succeeds, and `value id=saveTask` is no longer `[disabled]`.
- **Save with Return.** Run `$F ax <run> focus id=newTaskDraft`, `$F ax <run> key return`, and `$F ax <run> gone id=newTaskDraft`. The composer closes. `find "role=AXCheckBox,label=Book flights"` matches under the Work group, `value id=todayProgress` exposes `1 of 5 complete` (visible text `1/5 complete`), and `value status-item` has `title="1/5"`.
- **Stored row.** Run `$F snapshot <run> after-add`. In `db.txt`, `Book flights` is a new row with today's `day_key`, the next `display_order` for the day, `done` 0, and category `Work`.
- **Cancel a draft.** Run `$F ax <run> press id=addTask`, `$F ax <run> type "Discard me"`, `$F ax <run> key escape`, and `$F ax <run> gone id=newTaskDraft`. `find "label=Discard me"` returns nothing, and no row is added.
- **Complete.** Run `$F ax <run> press "role=AXCheckBox,label=Book flights"`. The checkbox value becomes `1`, `todayProgress` exposes `2 of 5 complete` (visible text `2/5 complete`), and the status item reads `2/5`. In a new snapshot, `done` is 1.
- **Edit.** Run `$F ax <run> press "label=Actions for task: Book flights"`, then `$F ax <run> press id=taskAction-edit`. An `id=editTaskDraft` field and an `id=editTaskCategory` pop-up appear. Run `$F ax <run> focus id=editTaskDraft`, `$F ax <run> key cmd+a`, `$F ax <run> type "Book train"`, and `$F ax <run> key return`. The row reads `Book train`, and in the snapshot the same rowid has the new text.
- **Delete.** Run `$F ax <run> press "label=Actions for task: Book train"` and `$F ax <run> press id=taskAction-delete`. An `id=taskDeletionConfirmation` group appears with `id=cancelTaskDeletion` and `id=confirmTaskDeletion`. Run `$F ax <run> press id=confirmTaskDeletion` and `$F ax <run> gone "label=Book train"`. Progress returns to `1/4`, and the row is gone from `db.txt`.
- **Keyboard routes.** Run `$F ax <run> key cmd+2`: `value id=laterTab` has value `1`. Run `$F ax <run> key cmd+1`: `todayTab` has value `1`. Run `$F ax <run> key cmd+n`: `id=newTaskDraft` appears. Run `$F ax <run> key escape` to close it.
- **Actions popover.** Run `$F ax <run> press "label=Actions for task: Review pull request"` and `$F ax <run> wait id=taskActionsPopover 3`. `find id^=taskAction-` lists Edit, Move Up, Move Down, `Move to General`, `Move to Work`, `Move to Errands`, and Delete…; `value id=taskAction-moveTo-<Work UUID>` is `[disabled]` with value `Current group`. Capture it with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/actions-popover.png id=taskActionsPopover`. Run `$F ax <run> key escape` and `$F ax <run> gone id=taskActionsPopover`: nothing changes in `db.txt`. Keyboard: `$F ax <run> focus "label=Actions for task: Review pull request"`, `key space` opens it with Edit highlighted, `key down` moves the highlight, `key return` acts on it. Clicking outside or on `…` again closes it without acting; pointer hover and outside clicks need a pointer and are Not tested through AX.
- **Persistence.** Run `$F stop <run>`, `$F snapshot <run> stopped`, `$F launch <run>`, and `$F snapshot <run> relaunched`. The two `db.txt` files are identical, and the window shows the same rows and progress.
- **Proof.** Capture `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/today.png`. Together with the snapshots and `actions.log`, it shows the action, the row, the count, and the stored state.

## Gotchas

- Every row has a six-dot drag handle. Reordering by dragging cannot be driven here; use the row popover's Move Up, Move Down, and Move To, and report pointer drags as Not tested.
- While editing, confirming a deletion, or managing categories, `addTask`, the tab control, History, and moves are disabled. Finish or cancel first, or the next press does nothing.
- Draft text is not saved data. A draft survives closing and reopening the window, but not Quit. Do not count it as persistence.
- Group order (General's position, custom categories' order) depends on the category ordering work. Assert membership and counts, not a group's index, unless order is the feature under test.
- `key cmd+a` selects the field's text only while the field has focus. Run `focus` first.
- `id=saveTask` is disabled while the draft is empty, and pressing it then does nothing. That is expected, not a failed press.
- The Category pop-up's AX value updates a moment after the menu choice. Wait for it, as in the recipe, before reading it.
