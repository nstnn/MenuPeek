# MenuPocket

MenuPocket is a local macOS menu bar app for a daily notes checklist. The checkout directory is named `MenuPeek`; the Xcode project and app are named `MenuPocket`. The desktop transition currently provides a reusable task-window shell; task layout and menu bar progress are pending. Existing notes remain stored in SQLite. See [current behavior and remaining MVP work](docs/REQUIREMENTS.md).

## Requirements

- macOS 14 or later and Xcode with its command-line tools selected.
- No account, network connection, third-party package, or paid Apple Developer membership is needed for a local build.

If the command-line tools point elsewhere, select your installed Xcode with `xcode-select --switch` before building.

## Build and run

Open `MenuPocket.xcodeproj` in Xcode, or run the local Debug launcher from this directory:

```bash
./run.sh
```

The launcher builds with the shared `MenuPocket` scheme into ignored `build/DerivedData`, stops this checkout's running Debug copy, and opens the rebuilt app. MenuPocket appears in the Dock. Its grid icon in the menu bar opens the task-window shell.

To run the hosted XCTest target:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

## Use the task-window shell

Click the menu bar grid icon or reopen MenuPocket from the Dock to show the same task window. Closing or minimizing it does not quit the app; another presentation restores it. The shell provides Settings access. Task layout, editing, and the menu bar count will arrive in later desktop-plan cards; the previous compact checklist is no longer exposed.

Saved notes and preferences are preserved. Notes stay assigned to their creation day in the sandbox's Application Support `MenuPocket/notes.sqlite`; preferences remain separate in `UserDefaults`. Settings retains Open at Login, app information, and Quit. Startup policy remains unchanged until the dedicated lifecycle card.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): current behavior, approved Notes MVP target, and gaps.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Notes MVP regression](docs/NOTES_MVP_REGRESSION.md): dated Debug build and hosted test results for the Task 11 handoff.
