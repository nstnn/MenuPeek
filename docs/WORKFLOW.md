# Development workflow

Use Xcode and the shared `MenuPocket` scheme on macOS 14 or later. The checkout directory is `MenuPeek`; build outputs belong under ignored `build/DerivedData`. [`run.sh`](../run.sh) builds and launches this checkout's Debug app. It is a local launcher, not a packaging or deployment script.

## Build and test

From the repository directory:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build

xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
```

The hosted tests cover note day boundaries, ordering, SQLite persistence and errors, observable state, preferences, demo loading, and login-item behavior through injected fakes. Tests must not modify the Mac's real login-item registration.

For a user-facing change, run the relevant tests and inspect the running app. In particular, exercise panel opening, notes writes and relaunch, empty and long lists, keyboard actions, Settings, and both appearances as applicable. Record unavailable UI or hardware checks as untested. Compilation and XCTest do not prove menu bar or Settings interaction.

## Local Release and login-item checks

Build a local Release app with the same scheme:

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The expected product path is `build/DerivedData/Build/Products/Release/MenuPocket.app`. This is a personal local build, not a Developer ID, notarized, App Store, or public distribution artifact. Inspect the built bundle's metadata, signature, and entitlements before a release claim. For login-item checks, use a stable installed copy and enable launch at login only when that change is intended. Approval status and registration are distinct from observing launch after a real login.

Keep source, build/test result, app identity, and hands-on UI observations together when making an acceptance claim. A rebuild after source changes makes earlier artifact and UI evidence stale.

## Documentation changes

Update [Requirements](REQUIREMENTS.md) when product behavior or scope changes, [Architecture](ARCHITECTURE.md) when component or data boundaries change, and this workflow when verification or release steps change. Keep [README](../README.md) concise and update [AGENTS.md](../AGENTS.md) only when its project-wide rules or document map changes.
