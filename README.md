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

The Today view shows the local date, progress, and a scrollable checklist. Incomplete tasks appear first, newest first within each group. Add task opens a single-line field; Return or Save stores trimmed text, and Escape or Cancel discards it. Checkboxes complete or uncomplete tasks. Row Edit and Delete actions provide text editing and deletion confirmation. A rejected write keeps the saved task/count and recoverable draft text, with an inline error.

Current-day new and edit drafts survive window close/reopen within the running process. Closing cancels deletion confirmation. Day changes or removed edit targets expose unsaved edit text for recovery. Quit/relaunch preserves saved tasks but does not promise recovery of unsaved drafts.

The menu bar shows saved completed/total progress, including `0/0` after a successful empty read. Unloaded or failed reads show `—`; open the window and use Retry. Failed writes retain the last saved count. Progress refresh remains active with the window closed. The previous compact editable popup is no longer exposed.

Tasks keep their assigned local day; unfinished tasks do not carry forward. Yesterday's unfinished count is informational. Existing notes remain in the sandbox's Application Support `MenuPocket/notes.sqlite`; preferences and onboarding state remain in `UserDefaults`.

Settings provides Open at Login, a Theme choice, a Quick Add switch, app information, and Quit. Theme defaults to System, which follows the macOS appearance; Light or Dark applies to the whole app immediately and is remembered across launches. Login startup initializes menu bar progress without raising tasks or Settings; the Dock icon remains visible. Actual login and interface evidence is recorded separately in [desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md).

| Shortcut | Action |
| --- | --- |
| Command-N | Restore the task window and focus Add task; unavailable during editing, deletion confirmation, or unavailable data. |
| Command-comma | Open the reusable Settings window. |
| Command-W | Close the active window while the app keeps running. |
| Command-Q | Quit the app. |
| Control-Option-N | With Quick Add on, show the capture panel from any app. |

Focused text fields support native cut/copy/paste/select-all and text undo/redo. Saved-task undo is outside this increment.

## Quick Add

Turn on Quick Add in Settings to add a task from any app without switching to MenuPocket. Press Control-Option-N, type the task in the small floating panel, and press Return to save it to today's list. Escape, Command-W, clicking outside, or pressing the shortcut again closes the panel and discards the text. Quick Add is off by default and the shortcut is fixed. If another app already holds the shortcut exclusively, Settings says so; quit that app, then turn the switch off and on to retry. MenuPocket cannot detect every conflict, such as system shortcuts.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): desktop behavior, daily-only scope, and acceptance criteria.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Desktop regression](docs/DESKTOP_TASK_REGRESSION.md): dated automated results and retained app identity.
- [Desktop acceptance](docs/DESKTOP_TASK_ACCEPTANCE.md): actual-interface evidence and remaining evidence gaps.
- Earlier Notes MVP records remain linked as history in the documentation index.
