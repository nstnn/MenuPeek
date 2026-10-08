# MenuPocket

MenuPocket is a local macOS desktop and menu bar app for daily tasks. Manage today's checklist and an undated Later list in one resizable task window, browse earlier days read-only in History, and see today's saved completed/total progress in the menu bar. Tasks stay in local SQLite storage. The checkout directory is named `MenuPeek`; the Xcode project and app are named `MenuPocket`. See the [product requirements](docs/REQUIREMENTS.md) for scope and the [desktop](docs/DESKTOP_TASK_ACCEPTANCE.md) and [Later](docs/LATER_TASKS_ACCEPTANCE.md) acceptance records for verification status.

## Requirements

- macOS 14 or later and Xcode with its command-line tools selected.
- No account, network connection, third-party package, or paid Apple Developer membership is needed for a local build.

If the command-line tools point elsewhere, select your installed Xcode with `xcode-select --switch` before building.

## Build and run

Open `MenuPocket.xcodeproj` in Xcode, or run the local Debug launcher from this directory:

```bash
./run.sh
```

The launcher builds with the shared `MenuPocket` scheme into ignored `build/DerivedData`, stops this checkout's running Debug copy, and opens the rebuilt app. MenuPocket appears in the Dock. Its saved completed/total count in the menu bar opens the task window on Today.

To run the hosted XCTest target:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

## Use the Today window

Opening MenuPocket explicitly shows the task window on Today. A `Today | Later` control at the top switches between the two lists in the same window. Clicking the menu bar progress count restores the window on Today; reopening from the Dock or Show Tasks restores it on the tab you last used. Closing or minimizing it leaves the app, Dock icon, and menu bar progress running. Quit from the application menu, Settings, or Command-Q to exit.

The Today view shows the local date, progress, and a scrollable checklist grouped by category. Custom categories appear in creation order, followed by General when populated. Tasks keep their original creation order within each group, including after completion, editing, or reassignment. Add task opens a single-line field and Category picker below progress, above the list; Return in the field or Save stores trimmed text and the selected category together, and Escape or Cancel discards the draft. Checkboxes complete or uncomplete tasks. Each row's “…” menu offers Edit to change text/category and Delete… to request inline confirmation. A rejected write keeps the saved task/count and draft text/category, with an inline error.

Use Manage categories… to create or rename reusable categories. Names must be nonblank, single-line, and unique ignoring case and canonically equivalent spelling. General is the built-in choice for tasks without a category and cannot be renamed or removed. Removing a custom category requires confirmation showing how many tasks across all days and Later will move to General; it keeps every task's text, completion, and day. Category names and renames are shared by both tabs.

Click a group header to collapse or expand its tasks. Its completed/total count and overall progress still include hidden rows. Only categories with tasks today have a group; the picker and manager show all saved categories. Collapsed groups and the category of the last successful new-task save from Today survive relaunch. A new draft starts in that category, or General if it no longer exists. A successful add or category reassignment expands its destination group; edits and Quick Add do not change the remembered category.

Current-day new and edit drafts retain text and category across window close/reopen within the running process. Closing cancels deletion and category-removal confirmations and dismisses the manager. Day changes or removed edit targets expose unsaved edit text and category context for recovery. If a category disappears, a new draft falls back visibly to General; an edit selecting that category moves to recovery. Quit/relaunch preserves saved tasks but does not promise recovery of unsaved drafts.

The menu bar shows saved completed/total progress, including `0/0` after a successful empty read. Unloaded or failed reads show `—`; open the window and use Retry. Failed writes retain the last saved count. Progress refresh remains active with the window closed. The previous compact editable popup is no longer exposed.

Right-click (or Control-click) the menu bar count for a read-only quick look: the date, Today's progress bar and `N of M done`, the next five unfinished Today tasks, how many Later tasks remain, and Open Today, Add Task… (always to Today), Settings…, and Quit. The quick look never completes or changes a task. Like other menu bar menus, it follows the macOS appearance rather than the Theme setting. VoiceOver and a few other checks are still untested (see [Requirements](docs/REQUIREMENTS.md#menu-bar-glance--implemented-2026-10-07)).

Today tasks keep their assigned local day; unfinished tasks do not carry forward. The yesterday reminder opens History at yesterday with the Unfinished filter. Existing notes remain in the sandbox's Application Support `MenuPocket/notes.sqlite`; preferences and onboarding state remain in `UserDefaults`.

## Use the Later list

Later holds work you want to keep without a date. A Later task has only text and an optional category: there is no deadline, planned date, reminder, or priority. Later tasks stay until you change them, across days and relaunches. The tab shows how many tasks remain, without a date or progress bar, and groups tasks by category like Today; groups with only completed tasks stay visible with zero remaining.

Add, complete, edit, and delete work as in Today. Each tab keeps its own new-task draft, category choice, collapsed groups, and errors. Switching tabs keeps new-task drafts; finish or cancel an inline edit, deletion confirmation, or Manage categories before switching. A day change does not cancel a Later edit or confirmation.

An unfinished Later task's “…” menu also offers Move to Today. It moves the task once, keeping its text and category, assigns it to the current day, and appends it to Today; the menu bar total rises by one. You stay in Later and see “Moved task to Today.” Completed Later tasks must be uncompleted before moving, and there is no move back from Today. Later-only changes never affect the menu bar count.

Settings provides Open at Login, a Theme choice, a Quick Add switch, app information, and Quit. Theme defaults to System, which follows the macOS appearance; Light or Dark applies to the whole app immediately and is remembered across launches. Login startup initializes menu bar progress without raising tasks or Settings; the Dock icon remains visible. Actual login and interface evidence is recorded separately in [desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md).

| Shortcut | Action |
| --- | --- |
| Command-1 / Command-2 | Restore the task window and select Today or Later (View menu), leaving History; unavailable while editing, confirming a deletion, or managing categories. |
| Command-N | Restore the task window, leaving History, and focus Add task in the selected tab (Today when no window exists); unavailable during editing, deletion confirmation, while Manage categories is open, or with unavailable data. |
| Command-comma | Open the reusable Settings window. |
| Command-W | Close the active window while the app keeps running. |
| Command-Q | Quit the app. |
| Control-Option-N | With Quick Add on, show the capture panel from any app. |

Focused text fields support native cut/copy/paste/select-all and text undo/redo. Saved-task undo is outside this increment.

## Browse history

Click the calendar button beside Today's date (View task history) to open History in the same window. It replaces the Today content with a History heading and Back to Today; Today's unsaved new-task draft, open composer, and scroll position are kept for your return. History is read-only: old tasks cannot be completed, edited, deleted, or moved.

History opens on yesterday in a Sunday-first month calendar. Each day shows completed/total for the tasks currently saved on that day: `0/0` for a past day with none, `—` for an empty future day, and Unavailable with Retry if the month could not be read. Use Previous month, Next month, and This month, or arrow keys, to move; click a day, or press Space or Return, to show its detail. Detail lists the day's tasks by current category in saved order. All, Unfinished, and Completed change only the rows shown; the day's count always covers every task.

Counts use each task's assigned day, not the day it was completed, and reflect tasks currently saved: deleted tasks are not counted, and renamed or removed categories show their current label or General. They are not a frozen end-of-day record.

Unfinished from previous days, inside History, lists every earlier day that still has unfinished tasks, newest first, 31 days at a time with Load more. Choosing a day opens its detail with the Unfinished filter; Back to Unfinished returns to the same list, and Go to Today returns to Today. The yesterday reminder on Today opens exactly yesterday with the Unfinished filter. Command-N, the menu bar count, the Dock, and Show Tasks always return to Today. History and Unfinished cannot be opened while you are editing a task, confirming a deletion, or managing categories.

## Quick Add

Turn on Quick Add in Settings to add a task from any app without switching to MenuPocket. Press Control-Option-N, type the task in the small floating panel, and press Return to save it to today's list in General. Quick Add always saves to Today, even while Later is selected, and leaves the selected tab, both drafts, and both remembered categories unchanged. Escape, Command-W, clicking outside, or pressing the shortcut again closes the panel and discards the text. Quick Add is off by default and the shortcut is fixed. If another app already holds the shortcut exclusively, Settings says so; quit that app, then turn the switch off and on to retry. MenuPocket cannot detect every conflict, such as system shortcuts.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): desktop behavior, Today/Later scope, and acceptance criteria.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Desktop regression](docs/DESKTOP_TASK_REGRESSION.md): dated automated results and retained app identity.
- [Desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md): actual-interface evidence and remaining evidence gaps.
- [Later regression](docs/LATER_TASKS_REGRESSION.md) and [Later acceptance](docs/LATER_TASKS_ACCEPTANCE.md): Today/Later automated and interface evidence.
- [Task categories handoff](docs/TASK_CATEGORIES_HANDOFF.md): implemented scope, dated verification, and remaining category acceptance checks.
- Earlier Notes MVP records remain linked as history in the documentation index.
