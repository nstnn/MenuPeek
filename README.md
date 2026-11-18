# MenuPocket

A native macOS task app with a daily checklist, a Later list, and progress in your menu bar.
Built with SwiftUI, AppKit, and SQLite. The repository is named `MenuPeek`; the app is `MenuPocket`.

## Features

- **Today & Later:** manage today's tasks and keep an undated list for another time.
- **Categories:** organize tasks into collapsible groups and reorder Today tasks or categories.
- **History:** browse past days and continue unfinished tasks without changing their original progress.
- **Menu bar:** see today's completed/total count; right-click for a quick look.
- **Quick Add:** capture a task from any app with Control-Option-N after enabling it in Settings.
- **Appearance:** System, Light, or Dark, with adjustable content zoom.

## Build and run

Requires **macOS 14+** and **Xcode** with its command-line tools selected. No third-party packages
or paid Apple Developer membership are needed for a local build.

```bash
git clone https://github.com/nstnn/MenuPeek.git
cd MenuPeek
./run.sh
```

You can also open `MenuPocket.xcodeproj` in Xcode and run the shared **MenuPocket** scheme.

To build Release and install in `/Applications`:

```bash
./install.sh
```

The installer backs up existing task data and preferences, replaces the installed app, and opens
it. Use `./install.sh --no-open` to install without launching.
See the [installation workflow](docs/WORKFLOW.md#local-release-and-login-item-checks) for details.

## Everyday use

Add tasks to Today or Later, check them off, and use each row's **…** menu to edit, move, or delete.
Move an unfinished Later task to Today when you're ready. Past tasks stay on their assigned day;
use **Continue today** in History to create a new attempt.

**Shortcuts:** ⌘N add task · ⌘1/⌘2 Today/Later · ⌘, Settings · ⌘+/⌘−/⌘0 zoom.

Closing the window keeps the app and menu bar count running. Use **⌘Q** to quit.

## Local by design

Tasks stay in a local SQLite database inside the app's sandbox. Preferences stay on your Mac.
No account or external service is required. Open at Login and Quick Add are optional settings.

## Documentation

- [Documentation index](docs/index.md) — feature guides, handoffs, and acceptance records.
- [Requirements](docs/REQUIREMENTS.md) — behavior and scope.
- [Architecture](docs/ARCHITECTURE.md) — state, storage, and system boundaries.
- [Development workflow](docs/WORKFLOW.md) — builds, tests, verification, and cleanup.

Some native and system checks remain unverified; see the acceptance records linked above.
