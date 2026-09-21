# MenuPocket

MenuPocket is a personal macOS menu bar app that displays deterministic demo
content. The checkout directory is named `MenuPeek`; the Xcode project, target,
and application are named `MenuPocket`.

## Requirements

- macOS 14.0 or later.
- Xcode with its command-line tools selected.
- Apple Silicon is the initial acceptance architecture.
- No third-party packages, network connection, account, or paid Apple Developer
  membership is required for the local build.

If Xcode is not selected, run this once with the appropriate local Xcode path:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## Open, build, and run

Open the shared project and scheme in Xcode:

```bash
open MenuPocket.xcodeproj
```

From the project directory, the local Debug launcher builds the app, stops only
the same checkout's running copy, and launches it:

```bash
./run.sh
```

The app has no Dock icon. Look for the MenuPocket grid icon in the menu bar.
Debug output is written to the ignored `build/DerivedData` directory.

For reproducible command-line builds, use the shared `MenuPocket` scheme:

```bash
xcodebuild \
  -project MenuPocket.xcodeproj \
  -scheme MenuPocket \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build

xcodebuild \
  -project MenuPocket.xcodeproj \
  -scheme MenuPocket \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

The local Release product is normally at:

```text
build/DerivedData/Build/Products/Release/MenuPocket.app
```

## Use the app

Click the MenuPocket menu bar item to open the content panel. The panel can
open Settings, refresh enabled modules, retry an individual failed module, or
quit the app.

Settings has three tabs:

- `Nội dung`: enable modules, change their order, choose the pinned module,
  and choose icon-only or icon-and-information display.
- `Chung`: view app information and manage `Mở khi đăng nhập`.
- `Demo`: select a scenario independently for each module and reload demo data.

The demo scenarios are `Bình thường`, `Không có dữ liệu`, `Lỗi`, and
`Phản hồi chậm`. Scenarios are session-only; saved product preferences restore
across relaunches.

## Run tests

Run the hosted XCTest target from the project directory:

```bash
xcodebuild \
  -project MenuPocket.xcodeproj \
  -scheme MenuPocket \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test
```

The test target is `MenuPocketTests`. Tests cover preference recovery,
ordering and pinning, loading states, cancellation and overlapping requests,
demo providers, and login-item state through injected fakes. They must not
change the host Mac's real login-item configuration.

## Install a personal Release build

The Release app is a local build, not a public distribution artifact. After
quitting other MenuPocket copies, copy the exact Release app to a stable
Applications location, preserving any existing copy until replacement is
intentional:

```bash
mkdir -p ~/Applications
cp -R build/DerivedData/Build/Products/Release/MenuPocket.app \
  ~/Applications/MenuPocket.app
```

Launch the installed copy before checking login-item behavior. In Settings,
enable `Mở khi đăng nhập` only when you explicitly want to change macOS login
configuration. If macOS requests approval, follow the Login Items instructions
and return to Settings to reread the state. Registration is separate from
proving that the app appeared automatically at a later login.

## Add a future module

Real integrations are intentionally deferred. A future module should:

1. Add a `ModuleDescriptor` with a new stable ID to the catalog.
2. Implement a `ModuleProvider` for its source.
3. Map source data to a `ModuleSnapshot`.
4. Add source-specific Settings only if needed.
5. Define that source's errors, permissions, and refresh policy.
6. Add provider and integration behavior tests.

Do not prebuild network access, token storage, caching, retry infrastructure,
background refresh, protected-data access, a database, or a backend before a
real content source requires it.

## v1 scope

This version is a local demo shell. It does not include external APIs,
authentication, cloud synchronization, AI, notes/tasks/timers, downloadable
plugins, user scripts, global shortcuts, notifications, multiple menu bar
items, automatic updates, telemetry, App Store/Developer ID distribution, or
notarization.

## Handoff evidence

The point-in-time implementation handoff is recorded in
`plan/task-030/report.md`. Build products, Xcode user state, and personal
signing material are intentionally excluded from source control.

For the full project guide, start with [`docs/index.md`](docs/index.md).
