# Categories

Categories are shared by Today, Later, and every saved day. Manage categories opens the right-hand pane where a user creates, renames, and removes custom categories. General is built in and cannot be renamed or removed. Removing a category asks for confirmation, states how many tasks will move to General, and keeps every task. Tasks show in collapsible category groups whose `completed of total` counts include hidden rows.

## Sub-features

- `cat-create` adds a unique, nonblank, single-line name; duplicates (ignoring case) are rejected inline.
- `cat-rename` renames in place, and every group and picker shows the new name.
- `cat-remove` confirms with a usage count, then moves those tasks to General.
- `cat-picker` lists General and every saved category in the composer and edit Category popover (`id=categoryPopover`), with the current choice checked.
- `cat-collapse` collapses or expands a group; the state survives relaunch.
- `cat-move-to` moves a Today task to another category from its row menu (Move To).
- `cat-manager-reorder` saves the shared custom-category order with a mouse drag/drop, including unused categories; General stays first.

## How to get to it (user POV)

- Choose `Categories` (`Manage categories`, the folder control in the Daybook rail) from any sidebar destination.
- Use the Category capsule in the add or edit composer.
- Click a group header to collapse or expand it.
- Use a Today row's `…` popover > Move To > category.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`, with categories `Work` and `Errands`.
- For final category native acceptance, use `--seed category-reordering` instead: the basic data plus `Unused`, a long-name Learning group with 24 Today tasks (one completed), Later tasks in Errands/Learning, and yesterday tasks in those two categories. This gives three populated custom groups, an empty manager row and a tall scroll case. Seed only a new database; relaunch the same run without reseeding. Work's manager preview remains 4; Learning's is 26, including completed tasks.
- `$F snapshot <run> before` has been taken.

- **Open manager.** Run `$F ax <run> press id=manageCategories` and `$F ax <run> wait id=categoryList`. The right-hand pane, headed `Categories`, shows `id=generalCategory`, rows `id^=categoryRow-`, a focused `id=newCategoryName`, a disabled `id=createCategory`, and `id=doneManagingCategories`. The Today/Later list is hidden from Accessibility while the pane is open: `find id=addTask` and `find id^=taskGroup-` return nothing (exit 2). The rail stays available.
- **Create.** Run `$F ax <run> focus id=newCategoryName`, `$F ax <run> type "Health"`, and `$F ax <run> press id=createCategory`. `find "label=Rename Health"` matches, and the field is empty again. The snapshot's `categories` table has a `Health` row.
- **Reject duplicate.** Type `work` and press Create. `value id=categoryNameError` reads `A category with this name already exists.`, and no row is added. Clear the field with `key cmd+a` before typing the next name.
- **Rename.** Run `$F ax <run> press "label=Rename Errands"`, `$F ax <run> wait id=renameCategoryName`, `$F ax <run> focus id=renameCategoryName`, `$F ax <run> key cmd+a`, `$F ax <run> type "Shopping"`, and `$F ax <run> press id=saveCategoryRename`. `wait "label=Rename Shopping"` succeeds. After `press id=doneManagingCategories`, `find "label~=Shopping\,"` matches the Today group header, for example `Shopping, 0 of 1 complete`.
- **Remove.** Reopen the manager and run `$F ax <run> press "label=Remove Work"`. `id=categoryRemovalConfirmation` appears with text `4 tasks, across all saved days and Later, use this category…` (two Today tasks, yesterday's report, and the Later offsite task) and the buttons `id=cancelCategoryRemoval` and `id=confirmCategoryRemoval`. Press confirm. In `db.txt`, `Work` is gone and those four tasks show category `General` with unchanged rowids, text, completion, and day.
- **Collapse.** Run `$F ax <run> press id=taskGroup-general`. `value id=taskGroup-general` reads `Collapsed`, and its task rows are gone from `tree`, while `todayProgress` is unchanged. In `defaults.plist`, `local.menupocket.app.taskCategories.collapsedGroupIDs` contains `general`. Relaunch the run: the group is still collapsed.
- **Move To.** Run `$F ax <run> press "label=Actions for task: Water the plants"`, then `$F ax <run> press id=taskAction-moveTo-<Errands category UUID>` or `press "role=AXButton,label=Move to Errands"` (the current category is `[disabled]` with the value `Current group`). The Errands header's count rises by one, for example `find "label~=Errands\, 0 of 2"`, and the snapshot shows the same rowid with category `Errands`.
- **Proof.** Screenshot the pane with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/categories-pane.png role=AXWindow` while it is open, plus before and after snapshots.

## Gotchas

- While the pane is open, task commands including Command-N are disabled. Idle sidebar navigation returns to Today/Later or opens History/Settings. During rename or removal confirmation these destinations are disabled until Save/Cancel. `doneManagingCategories` also returns to the retained list.
- The popover's Move To items show the category name and are labeled `Move to <name>` for Accessibility. Open the right row's popover immediately before pressing.
- A `Work` label can also match the Category popover's items, the Work group header, or a row popover's `Move to Work`. Use `id^=categoryOption-,label=Work` and close other popovers with `key escape` first.
- Reordering categories by drag in the manager is pointer-only and cannot be driven here. Report it as Not tested, or give the user manual steps, and check `categories.creation_order` in `db.txt` for the stored order.
- Removing a category changes saved data on every day. Use a fresh run when another recipe needs the seeded categories.

## Category drag sources (TASK-006; immediate-drag revision)

Today/Later custom-group headers and only their outer padding (12 pt top/bottom, 16 pt sides) accept pointer drags after at least 4 pt movement, without a hold delay or source highlight. There is no category handle. The existing header Button still owns accessibility/keyboard disclosure. General has no source. Manage categories mounts the same source/target with its own idle-pane guards (TASK-008). Today/Later accept category drops through TASK-007; source start alone saves nothing.

On an isolated fixture, use actual pointer input with the window active:

1. Click Work: disclosure toggles once. Restore the original collapse state. Move less than 4 pt before releasing: it still clicks once.
2. Press its header, keep it stationary for more than 300 ms, and release: disclosure toggles once, with no armed highlight. Restore the original state. Press and immediately move at least 4 pt: dragging starts without waiting, and release must not toggle disclosure.
3. Press and drag on the header and empty outer padding, including while collapsed. Neither a stationary press nor an active drag tints the source header. The compact preview shows name and total task count including completed rows. Escape or outside release saves nothing. Repeat on Later.
4. Select task text, toggle/restore a checkbox, open/close Actions, and use composer fields. These regions must not start category drag. General remains ordinary disclosure input.
5. Close/reopen the window, switch destination, or begin editing: candidates lose authorization. A native reservation remains until AppKit source-end; another task/category drag cannot overlap it. After native end, a fresh drag can start.

Take before/after SQLite and defaults snapshots; category ranks and task fields must be identical, and collapse defaults must match after explicitly restoring short-click checks. `mpax press` proves accessibility disclosure only; it cannot establish immediate pointer dragging or native drag. Hosted lifecycle tests are supporting evidence; unobserved physical gestures remain Not tested for TASK-010. Save the exact source/artifact identity and clean the fixture after every session.

## Category drop routing (TASK-007)

On Today/Later, press and immediately drag a custom header or its empty outer padding over the upper/lower half of another visible group. The accent insertion line appears at that group's top/bottom boundary, outside task rows. The gap after General offers before the first visible custom UUID; the upper half of General rejects drops. Gaps after custom groups offer after that UUID. Hidden categories remain in the full saved catalog with UUID anchors; they do not appear as empty targets. General has no category source. Task handles and targets remain separate.

Using an identified isolated fixture, take before/after snapshots for these physical checks:

1. Move Errands before Work on Today; confirm the new visible order and `categories.creation_order`, with General first. Collapse a source first and confirm it stays collapsed after moving.
2. On Later, use at least two populated custom categories (create a fictional task through the composer if needed). Reorder first/last custom groups and check Today, picker and retained History consume the same saved order.
3. Drag from a tall-group header/background, move near viewport edges, and observe clamped scrolling and insertion feedback recomputed after scrolling. After a changed save only, its small header target is revealed without expanding or taking text focus.
4. Escape, leave the authorized list, release outside, and drop at an equivalent position: ranks, revision, collapse and drafts stay unchanged. A new drag/drop must work after native source-end. Exercise edit/removal/context guards and an injected failed repository save in focused hosted tests; native failure/retry remains TASK-010 when a UI failure fixture is available.
5. Verify task checkbox, text selection, Actions, composer and existing task pointer drag coexist. Quit/relaunch the same fixture without reseeding and compare saved category order, task rows and scoped defaults.

`mpax` cannot generate category drags. Callback tests prove routing/authorization/storage dispatch, not native negotiation or physical scrolling. Record each physical case as observed Pass/Fail or Not tested; broader final acceptance remains TASK-010. Clean fixtures and Debug hosts even when access fails.

## Manage categories mouse reorder (TASK-008)

The custom row's label and its vertical background padding accept the same immediate drag at 4 pt movement, without a timer or source highlight. Rename/Remove buttons and name fields retain ordinary input. General has no source; its lower half offers before the first custom UUID. Every custom row, including unused categories, offers before/after placement. Targets use the manager's scroll view for edge scrolling; a committed changed move reveals its row without changing field focus or drafts. No keyboard reorder actions are added.

On an isolated basic fixture:

1. Open Manage categories, create `Unused`, then type `Pending category` into `newCategoryName` without creating it. Press and immediately drag Unused's label/padding and drop before Work. Check General remains first, the new-name draft remains, and `categories.creation_order` stores Unused/Work/Errands. Task rows and preferences must match the pre-drop snapshot.
2. Drag Work to inspect its preview count: all saved days and Later assignments count, including completed tasks (4 with the unchanged basic seed). Do not count only visible Today rows. Cancel without saving.
3. Rename/Remove remain clickable, rename text stays editable, and rename/removal confirmation blocks drags and drops. Cancel each action, then try a fresh drag. Done/dismissal cancels authorization; normal task/category drags resume after native source-end.
4. With many fictional categories, observe sheet edge scrolling and committed row reveal. Long names must leave Rename/Remove available. Escape/outside/equivalent drop preserves rank and typed drafts. Focused hosted checks exercise usage-read failure and failed save/retry; physical failure/retry needs a fixture that injects those errors.
5. Close/reopen the manager and quit/relaunch the same fixture without reseeding. Check saved order, picker order and unchanged task rows/defaults. Take snapshots and clean every fixture.

Accessibility button/field checks establish ordinary controls only. Physical holds, target negotiation, scrolling/reveal, and preservation of the sheet draft through an actual native drop need observed pointer evidence; mark them Not tested when unavailable. Final physical acceptance remains TASK-010.

## Integrated automated preservation (TASK-009)

`TaskHistoryIntegrationTests.testCommittedCategoryOrderReloadsRetainedHistoryAndPreservesTasksAcrossFailureRetryAndReopen` uses real SQLite and shared state with an isolated defaults suite. It seeds sparse category/task ranks, unused and long-name categories, General, completed Today/Later tasks and an older day. It checks stale/equivalent requests, a rank-write trigger failure and a reader-lock COMMIT failure before a successful retry; retained History, Today/Later groups and category options then consume the saved order. Explicit create/rename/remove operations are accounted for separately before reopening the changed database and defaults through fresh state. Raw rowids and every task field/rank, category non-rank fields, schema and preferences are compared.

Run this with the shared scheme's History integration, SQLite, daily state, movement, grouping and glance suites. This is automated source/storage evidence; native holds, drops, scrolling, control coexistence and quit/relaunch in the real interface remain TASK-010. Clean the temporary test host after each session, retaining logs/results and binary identity.
