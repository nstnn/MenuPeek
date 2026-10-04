# MenuPocket

MenuPocket is a local macOS desktop and menu bar app for daily tasks. Manage today's checklist in one resizable task window and see saved completed/total progress in the menu bar. Tasks stay in local SQLite storage. The checkout directory is named `MenuPeek`; the Xcode project and app are named `MenuPocket`. See the [product requirements](docs/REQUIREMENTS.md) for scope and the [desktop acceptance record](docs/DESKTOP_TASK_ACCEPTANCE.md) for verification status.

## Requirements

- macOS 14 or later and Xcode with its command-line tools selected.
- No account, network connection, third-party package, or paid Apple Developer membership is needed for a local build.

If the command-line tools point elsewhere, select your installed Xcode with `xcode-select --switch` before building.

## Build and run

Open `MenuPocket.xcodeproj` in Xcode, or run the local Debug launcher from this directory:

```bash
./run.sh
```

The launcher builds with the shared `MenuPocket` scheme into ignored `build/DerivedData`, stops this checkout's running Debug copy, and opens the rebuilt app. MenuPocket appears in the Dock. Its saved completed/total count in the menu bar opens the Today task window.

To run the hosted XCTest target:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

## Use the Today window

Opening MenuPocket explicitly shows the Today task window. Click the menu bar progress count or reopen MenuPocket from the Dock to restore the same window. Closing or minimizing it leaves the app, Dock icon, and menu bar progress running. Quit from the application menu, Settings, or Command-Q to exit.

The Today view shows the local date, progress, and a scrollable checklist grouped by category. Custom categories appear in creation order, followed by General when populated. Tasks keep their original creation order within each group, including after completion, editing, or reassignment. Add task opens a single-line field and Category picker below progress, above the list; Return in the field or Save stores trimmed text and the selected category together, and Escape or Cancel discards the draft. Checkboxes complete or uncomplete tasks. Each row's “…” menu offers Edit to change text/category and Delete… to request inline confirmation. A rejected write keeps the saved task/count and draft text/category, with an inline error.

Use Manage categories… to create or rename reusable categories. Names must be nonblank, single-line, and unique ignoring case and canonically equivalent spelling. General is the built-in choice for tasks without a category and cannot be renamed or removed. Removing a custom category requires confirmation showing how many tasks across all days will move to General; it keeps every task's text, completion, and day.

Click a group header to collapse or expand its tasks. Its completed/total count and overall progress still include hidden rows. Only categories with tasks today have a group; the picker and manager show all saved categories. Collapsed groups and the category of the last successful new-task save from Today survive relaunch. A new draft starts in that category, or General if it no longer exists. A successful add or category reassignment expands its destination group; edits and Quick Add do not change the remembered category.

Current-day new and edit drafts retain text and category across window close/reopen within the running process. Closing cancels deletion and category-removal confirmations and dismisses the manager. Day changes or removed edit targets expose unsaved edit text and category context for recovery. If a category disappears, a new draft falls back visibly to General; an edit selecting that category moves to recovery. Quit/relaunch preserves saved tasks but does not promise recovery of unsaved drafts.

The menu bar shows saved completed/total progress, including `0/0` after a successful empty read. Unloaded or failed reads show `—`; open the window and use Retry. Failed writes retain the last saved count. Progress refresh remains active with the window closed. The previous compact editable popup is no longer exposed.

Tasks keep their assigned local day; unfinished tasks do not carry forward. Yesterday's unfinished count is informational. Existing notes remain in the sandbox's Application Support `MenuPocket/notes.sqlite`; preferences and onboarding state remain in `UserDefaults`.

Settings provides Open at Login, a Theme choice, a Quick Add switch, app information, and Quit. Theme defaults to System, which follows the macOS appearance; Light or Dark applies to the whole app immediately and is remembered across launches. Login startup initializes menu bar progress without raising tasks or Settings; the Dock icon remains visible. Actual login and interface evidence is recorded separately in [desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md).

| Shortcut | Action |
| --- | --- |
| Command-N | Restore the task window and focus Add task; unavailable during editing, deletion confirmation, while Manage categories is open, or with unavailable data. |
| Command-comma | Open the reusable Settings window. |
| Command-W | Close the active window while the app keeps running. |
| Command-Q | Quit the app. |
| Control-Option-N | With Quick Add on, show the capture panel from any app. |

Focused text fields support native cut/copy/paste/select-all and text undo/redo. Saved-task undo is outside this increment.

## Quick Add

Turn on Quick Add in Settings to add a task from any app without switching to MenuPocket. Press Control-Option-N, type the task in the small floating panel, and press Return to save it to today's list in General. Quick Add leaves the Today window's remembered category unchanged. Escape, Command-W, clicking outside, or pressing the shortcut again closes the panel and discards the text. Quick Add is off by default and the shortcut is fixed. If another app already holds the shortcut exclusively, Settings says so; quit that app, then turn the switch off and on to retry. MenuPocket cannot detect every conflict, such as system shortcuts.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): desktop behavior, daily-only scope, and acceptance criteria.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Desktop regression](docs/DESKTOP_TASK_REGRESSION.md): dated automated results and retained app identity.
- [Desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md): actual-interface evidence and remaining evidence gaps.
- [Task categories handoff](docs/TASK_CATEGORIES_HANDOFF.md): implemented scope, dated verification, and remaining category acceptance checks.
- Earlier Notes MVP records remain linked as history in the documentation index.
