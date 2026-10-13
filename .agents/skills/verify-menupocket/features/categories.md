# Categories

Categories are shared by Today, Later, and every saved day. Manage categories opens a sheet where a user creates, renames, and removes custom categories. General is built in and cannot be renamed or removed. Removing a category asks for confirmation, states how many tasks will move to General, and keeps every task. Tasks show in collapsible category groups whose `completed of total` counts include hidden rows.

## Sub-features

- `cat-create` adds a unique, nonblank, single-line name; duplicates (ignoring case) are rejected inline.
- `cat-rename` renames in place, and every group and picker shows the new name.
- `cat-remove` confirms with a usage count, then moves those tasks to General.
- `cat-picker` lists every saved category in the composer and edit pop-ups.
- `cat-collapse` collapses or expands a group; the state survives relaunch.
- `cat-move-to` moves a Today task to another category from its row menu (Move To).

## How to get to it (user POV)

- Choose `Manage categories` (the folder button beside Add task) in Today or Later.
- Use the Category pop-up in the add or edit composer.
- Click a group header to collapse or expand it.
- Use a Today row's `…` menu > Move To > category.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`, with categories `Work` and `Errands`.
- `$F snapshot <run> before` has been taken.

- **Open manager.** Run `$F ax <run> press id=manageCategories` and `$F ax <run> wait id=categoryList`. A sheet headed `Manage categories` shows `id=generalCategory`, rows `id^=categoryRow-`, a focused `id=newCategoryName`, a disabled `id=createCategory`, and `id=doneManagingCategories`. Behind the sheet, `addTask` and the group headers are `[disabled]`.
- **Create.** Run `$F ax <run> focus id=newCategoryName`, `$F ax <run> type "Health"`, and `$F ax <run> press id=createCategory`. `find "label=Rename Health"` matches, and the field is empty again. The snapshot's `categories` table has a `Health` row.
- **Reject duplicate.** Type `work` and press Create. `value id=categoryNameError` reads `A category with this name already exists.`, and no row is added. Clear the field with `key cmd+a` before typing the next name.
- **Rename.** Run `$F ax <run> press "label=Rename Errands"`, `$F ax <run> wait id=renameCategoryName`, `$F ax <run> focus id=renameCategoryName`, `$F ax <run> key cmd+a`, `$F ax <run> type "Shopping"`, and `$F ax <run> press id=saveCategoryRename`. `wait "label=Rename Shopping"` succeeds. After `press id=doneManagingCategories`, `find "label~=Shopping\,"` matches the Today group header, for example `Shopping, 0 of 1 complete`.
- **Remove.** Reopen the manager and run `$F ax <run> press "label=Remove Work"`. `id=categoryRemovalConfirmation` appears with text `4 tasks, across all saved days and Later, use this category…` (two Today tasks, yesterday's report, and the Later offsite task) and the buttons `id=cancelCategoryRemoval` and `id=confirmCategoryRemoval`. Press confirm. In `db.txt`, `Work` is gone and those four tasks show category `General` with unchanged rowids, text, completion, and day.
- **Collapse.** Run `$F ax <run> press id=taskGroup-general`. `value id=taskGroup-general` reads `Collapsed`, and its task rows are gone from `tree`, while `todayProgress` is unchanged. In `defaults.plist`, `local.menupocket.app.taskCategories.collapsedGroupIDs` contains `general`. Relaunch the run: the group is still collapsed.
- **Move To.** Run `$F ax <run> press "label=Actions for task: Water the plants"`, then `$F ax <run> press "role=AXMenuItem,label=Errands"` (the Move To submenu items are searched too, and the current category is `[disabled]`). The Errands header's count rises by one, for example `find "label~=Errands\, 0 of 2"`, and the snapshot shows the same rowid with category `Errands`.
- **Proof.** Screenshot the sheet with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/categories-sheet.png role=AXSheet` while it is open, plus before and after snapshots.

## Gotchas

- While the sheet is open, the window's other controls are disabled and Command-N does nothing. Press `doneManagingCategories` before driving Today again.
- The Move To submenu's items are titled by category name only, and the row menu also has items named like categories. Open the right row's menu immediately before pressing.
- A `Work` menu item title can also match the composer's Category pop-up items if a pop-up is open. Close other menus with `key escape` first.
- Reordering categories by drag in the manager is pointer-only and cannot be driven here. Report it as Not tested, or give the user manual steps, and check `categories.creation_order` in `db.txt` for the stored order.
- Removing a category changes saved data on every day. Use a fresh run when another recipe needs the seeded categories.

## Category hold sources (TASK-006)

Today/Later custom-group headers and only their outer padding (12 pt top/bottom, 16 pt sides) accept pointer holds. There is no category handle. The existing header Button still owns accessibility/keyboard disclosure. General has no source. Manage categories source mounting and accepting category drops are later cards; TASK-006 starts transient drags only and saves nothing.

On an isolated fixture, use actual pointer input with the window active:

1. Short-click Work: disclosure toggles once. Restore the original collapse state.
2. Hold its header for at least 300 ms then release without moving: disclosure stays unchanged. Move at least 4 pt before 300 ms: neither disclosure nor category drag starts.
3. Hold then move on the header and empty outer padding, including while collapsed. The compact preview shows name and total task count including completed rows. Escape or outside release saves nothing. Repeat on Later.
4. Select task text, toggle/restore a checkbox, open/close Actions, and use composer fields. These regions must not start category drag. General remains ordinary disclosure input.
5. Close/reopen the window, switch destination, or begin editing: candidates lose authorization. A native reservation remains until AppKit source-end; another task/category drag cannot overlap it. After native end, a fresh drag can start.

Take before/after SQLite and defaults snapshots; category ranks and task fields must be identical, and collapse defaults must match after explicitly restoring short-click checks. `mpax press` proves accessibility disclosure only; it cannot establish pointer hold timing or native drag. Hosted lifecycle tests are supporting evidence; unobserved physical gestures remain Not tested for TASK-010. Save the exact source/artifact identity and clean the fixture after every session.
