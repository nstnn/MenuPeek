# MenuPocket

MenuPocket is a local macOS desktop and menu bar app for daily tasks. The checkout directory is named `MenuPeek`; the Xcode project and app are named `MenuPocket`. The desktop transition provides a resizable Today task window; editing and menu bar progress remain pending. Existing notes remain stored in SQLite. See [current behavior and remaining MVP work](docs/REQUIREMENTS.md).

## Requirements

- macOS 14 or later and Xcode with its command-line tools selected.
- No account, network connection, third-party package, or paid Apple Developer membership is needed for a local build.

If the command-line tools point elsewhere, select your installed Xcode with `xcode-select --switch` before building.

## Build and run

Open `MenuPocket.xcodeproj` in Xcode, or run the local Debug launcher from this directory:

```bash
./run.sh
```

The launcher builds with the shared `MenuPocket` scheme into ignored `build/DerivedData`, stops this checkout's running Debug copy, and opens the rebuilt app. MenuPocket appears in the Dock. Its grid icon in the menu bar opens the Today task window.

To run the hosted XCTest target:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

## Use the Today window

Click the menu bar grid icon or reopen MenuPocket from the Dock to show the same task window. Closing or minimizing it does not quit the app; another presentation restores it. The Today view shows the local date, saved task progress, and ordered tasks in a scrollable list, with Settings access and Retry when tasks cannot load. Add task opens a single-line field: Return or Save adds trimmed text; Escape or Cancel discards it. Checkboxes complete or uncomplete tasks and update saved progress. Failed writes preserve draft text or the saved checkbox/count and show an inline error. Unsaved new-task text survives closing and reopening the window within the running app. Editing/deletion and the menu bar count remain pending. The previous compact checklist is no longer exposed.

Saved notes and preferences are preserved. Notes stay assigned to their creation day in the sandbox's Application Support `MenuPocket/notes.sqlite`; preferences remain separate in `UserDefaults`. Settings retains Open at Login, app information, and Quit. Startup policy remains unchanged until the dedicated lifecycle card.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): current behavior, approved Notes MVP target, and gaps.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Notes MVP regression](docs/NOTES_MVP_REGRESSION.md): dated Debug build and hosted test results for the Task 11 handoff.
