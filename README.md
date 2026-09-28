# MenuPocket

MenuPocket is a local macOS menu bar app for a daily notes checklist. The checkout directory is named `MenuPeek`; the Xcode project and app are named `MenuPocket`. The current notes panel stores data in SQLite. See [current behavior and remaining MVP work](docs/REQUIREMENTS.md).

## Requirements

- macOS 14 or later and Xcode with its command-line tools selected.
- No account, network connection, third-party package, or paid Apple Developer membership is needed for a local build.

If the command-line tools point elsewhere, select your installed Xcode with `xcode-select --switch` before building.

## Build and run

Open `MenuPocket.xcodeproj` in Xcode, or run the local Debug launcher from this directory:

```bash
./run.sh
```

The launcher builds with the shared `MenuPocket` scheme into ignored `build/DerivedData`, stops this checkout's running Debug copy, and opens the rebuilt app. MenuPocket has no Dock icon; use its grid icon in the menu bar.

To run the hosted XCTest target:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

## Use the notes panel

Click the menu bar icon to see today's notes, completed/total progress, and the count of unfinished notes from yesterday. `Add note` opens a single-line composer. Press Return or `Save` to store a nonempty note; Escape cancels. Check a note to complete it, or use its row menu to edit or delete it. Deletion asks for confirmation. The Settings gear opens the retained Settings window.

Notes are local to this Mac and stay assigned to their creation day; unfinished notes do not move into today's list. The SQLite database is `MenuPocket/notes.sqlite` under the app's sandboxed Application Support directory. App preferences are stored separately in `UserDefaults`. If a note write fails, the panel shows an error and keeps the unsaved draft. Settings provides Open at Login, app information, and Quit.

## Project documentation

- [Documentation index](docs/index.md): where each topic lives.
- [Requirements](docs/REQUIREMENTS.md): current behavior, approved Notes MVP target, and gaps.
- [Architecture](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [Workflow](docs/WORKFLOW.md): development checks and local Release procedure.
- [Notes MVP regression](docs/NOTES_MVP_REGRESSION.md): dated Debug build and hosted test results for the Task 11 handoff.
