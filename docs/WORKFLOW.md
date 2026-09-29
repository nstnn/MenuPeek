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

The hosted tests cover note day boundaries, ordering, SQLite persistence and errors, observable state, preferences, demo loading, and login-item behavior through injected fakes. Tests must not modify the Mac's real login-item registration. The Debug XCTest host skips production delegate initialization; lifecycle tests supply isolated daily repositories, defaults, launch context, and login services. Tests that start a delegate must clean up its windows/status item and restore native menus.

For a user-facing change, run the relevant tests and inspect the running app. In particular, exercise task-window opening, task writes and relaunch, empty and long lists, Command-N/W/Q/comma, native text editing, Settings reuse, and both appearances as applicable. Check explicit launch versus quiet login startup separately, without changing real login registration to seed an automated test. Record unavailable UI or hardware checks as untested. Compilation and XCTest do not prove menu bar or Settings interaction.

## GitHub CI

[`ci.yml`](../.github/workflows/ci.yml) runs on pull requests targeting `main`, pushes to `main` (including merged PRs), and manual runs from the Actions tab once the workflow is on the default branch. For PRs, the default checkout tests GitHub's proposed merge with the target branch. New commits to the same PR or branch cancel its older CI run.

The single `Build and test` job uses GitHub's `macos-15` arm64 runner and selects Xcode 16.4 with `DEVELOPER_DIR`. This version is listed in the [runner image's installed software](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md); update the runner and toolchain together when needed. The job prints the toolchain, builds and runs the Debug hosted XCTest suite with the shared `MenuPocket` scheme, then builds Release. The project retains its existing ad hoc signing, so these checks require no Apple signing secrets. Build outputs remain under `build/DerivedData`.

The workflow has read-only repository permissions and a 20-minute job timeout. A build or test failure fails the check; inspect the failed step's log in Actions or the PR's Checks view. There are no path filters, so a documentation-only PR also receives a check. See GitHub's [workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) and [concurrency behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

Commit and push the workflow to activate it on GitHub, then confirm a real run succeeds. Local command verification does not verify GitHub's runner environment. To require passing CI before merging, separately configure branch protection or a ruleset to require the `Build and test` status check after it has run. Adding the workflow alone does not enforce this merge rule. CI covers automated checks; continue the hands-on interface and login-item checks described here before making acceptance claims. The Release step builds a local-style app and does not publish or notarize it.

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
