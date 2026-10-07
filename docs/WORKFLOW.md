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

The hosted tests cover note day boundaries, ordering, SQLite persistence and errors, shared-state availability and refresh, repeated status-count observation, window/lifecycle/native commands, preferences, demo loading, login-item behavior, and Quick Add registration, capture panel, and add path through injected fakes. Tests must not modify the Mac's real login-item registration or register a real global hotkey. `AppModel` defaults to the Carbon hotkey service, so every test that turns Quick Add on injects `FakeHotKeyService`, and service tests use a fake `HotKeySystemAccess`; constructing the Carbon service registers nothing. The Debug XCTest host skips production delegate initialization; lifecycle tests supply isolated daily repositories, defaults, launch context, and login and hotkey services. Tests that start a delegate must clean up its windows, Quick Add panel, and status item and restore native menus and the application appearance.

For a user-facing change, run the relevant tests and inspect the running app. In particular, exercise task-window opening, task writes and relaunch, empty and long lists, Command-N/W/Q/comma, native text editing, Settings reuse, and both appearances as applicable. For a theme change, check each Theme choice against the macOS appearance, including the menu bar count and a relaunch. For a Quick Add change, press Control-Option-N with another app frontmost, with the Today window or Settings key, and over a full-screen app. Check that MenuPocket does not become active, that Return saves and updates the menu bar count, that Escape, Command-W, clicking outside, and a second press discard the text, that native editing works and Command-Q/N/comma do nothing, and that a half-typed Today draft survives a capture. To check conflict reporting, register the same key from a throwaway process kept outside the repository and the app, once shared and once exclusive, and quit it between cases. Check explicit launch versus quiet login startup separately, without changing real login registration to seed an automated test. Record unavailable UI or hardware checks as untested. Compilation and XCTest do not prove menu bar, Settings, or global hotkey interaction.

## Test artifact cleanup

Cleanup is part of completing every build/test/UI verification session, whether checks pass or fail. Identify the user's main app by its exact bundle and running path before testing; a `MenuPocket.app` name or bundle ID alone cannot distinguish it from a test host. Reuse `build/DerivedData` for routine checks when doing so will not overwrite the main app. Create separate outputs only when isolation requires them, and track every temporary Debug/Release host, baseline app, and renamed fixture you create.

Before reporting completion:

1. Finish any relaunch/persistence checks, save the required logs, `.xcresult` files, screenshots, and artifact identity, then quit each temporary app and confirm its process has exited. Do not move an app while a build or test is using it.
2. Unregister each temporary app's exact path from LaunchServices and move the `.app` bundle to macOS Trash using `FileManager.trashItem`. Preserve source, evidence, the main app, saved databases, preferences, and login-item state. Remove your own test bundles; do not sweep another active session's artifacts unless the user explicitly requests a wider cleanup.
3. Unregister the resulting Trash paths after moving the apps, since macOS can register them again. Verify the temporary original paths are gone and Spotlight/LaunchServices no longer expose them as runnable copies. Verify the main app remains intact; report any cleanup blocker instead of silently leaving test apps behind.

Do not keep test apps for possible future use or leave them installed in `/Applications`. A user-requested final app is the retained product; disposable verification copies must be cleaned up without emptying Trash or deleting saved user data.

## Category verification

Use the shared scheme above for category domain, SQLite migration/transactions, coherent daily reads, grouping, draft recovery, presentation preferences, and hosted window/manager checks. For native scenarios, use the production views/state with an isolated SQLite database and defaults suite, injected clock, and fake login/hotkey services. Verify the fixture's running path, bundle/hash, database, and defaults before changing assignments; removal affects every saved day. Fixture identities and data must remain separate from the production sandbox.

Exercise create/duplicate/rename/remove, categorized add/edit/reassignment and category-only edits, collapse/counts, destination expansion, last-used selection, cancelled/failed writes, unavailable-read recovery, stale category/target/day recovery, and manager command guards. Check same-day close/reopen with text/category drafts. Check minimum size, long names/text, many/empty/General-only/all-completed groups, keyboard/native editing, focus, Settings, and light/dark appearance. Count and confirmation assertions alone do not establish visible usability.

For saved-data persistence, make actual isolated changes, quit the fixture completely, confirm process exit, and relaunch the same identified artifact without reseeding. Compare stopped/relaunched task and category IDs, assignments, rowids/order, text, day, timestamps, completion/counts, and both presentation preferences. Check the visible result and a fresh blank draft's remembered category. Unsaved drafts are process-local and need not survive Quit. An unchanged seed or headless reopen is narrower evidence than this changed-data/interface check.

Category preferences use `local.menupocket.app.taskCategories.lastUsedCategoryID` (UUID string; absent means General) and `local.menupocket.app.taskCategories.collapsedGroupIDs` (category UUID strings plus `general`). They are separate from schema-1 `AppPreferences` and SQLite schema v4. A fixture must use an isolated defaults suite for these keys as well as existing preferences/onboarding, preserving the real user's values. Missing/deleted choices fall back safely; Quick Add saves to General without changing the remembered Today choice.

Record automated, native-fixture, production-identity, and genuine-system outcomes separately. The [category handoff](TASK_CATEGORIES_HANDOFF.md) owns the current evidence summary and remaining gate; the dated desktop records retain the detailed results. TASK-012 documentation completion does not substitute for TASK-011 interface acceptance.

## Schema v4 upgrade preparation

Migration verification uses only temporary databases through the shared scheme; the Debug XCTest host does not initialize production storage. Before the first real-data launch of a v4 build, quit the app completely and prepare a verified, consistent recoverable copy of `notes.sqlite` and relevant SQLite sidecars. Record the backup location and database/build identity. Movement verification uses isolated migration and repository fixtures only; production launch and backup/restore remain separate authorized work.

Fresh stores and compatible v0/v1/v2/v3 stores reach v4 in one transaction. Required category and Later steps run only for their original versions. The ordering step adds integer `notes.display_order`, backfills each day's ranks from rowid order, and creates unique `(day_key, display_order)` index `notes_day_display_order_idx`. Existing task fields/rowids, categories, Later rows and defaults/login state are preserved. Reopen validates schema, integrity and nonnegative unique ranks without renumbering; unsupported or incompatible stores are refused without repair. Daily reads validate integer, nonnegative, unique ranks and return saved display order. Explicit movement validates a fresh transactional snapshot, changes category and ranks together, and returns a snapshot only after COMMIT. Rejected/equivalent moves perform no updates. Add and Quick Add allocate after the current daily maximum; Int64 exhaustion compacts only that day in saved order inside the insertion transaction. Text/completion edits and surviving rows after deletion/category removal retain their ranks. State/UI movement remains subsequent work.

Older schema-v1/v2/v3 binaries cannot reopen v4. Do not downgrade/reset the database or promise backward binary compatibility. Restoring a pre-upgrade backup is a separate deliberate action that loses post-backup changes.

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

Record automated results in [Desktop regression](DESKTOP_TASK_REGRESSION.md) and actual-interface results in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md). Identify the source revision and dirty inputs, configuration, toolchain, version/build, app path, executable/bundle hashes, timestamp, and running path/PID as applicable. Distinguish an installed production-identity app from fixtures using another bundle ID, database, defaults suite, or sandbox arrangement. Keep screenshots/observations tied to the artifact; a process snapshot alone does not identify which UI action succeeded.

Use Pass, Fail, Not tested, or Blocked for checks with recorded outcomes. A dependency completion assumption is not an observed result. A genuine login, day transition, display configuration, or VoiceOver check needs its own evidence; injected contexts and registration status remain supporting automated facts. Retain the essential identity and results in tracked documents even when raw logs, app bundles, or screenshots remain under ignored `build/`.

## Documentation changes

Update [Requirements](REQUIREMENTS.md) when product behavior or scope changes, [Architecture](ARCHITECTURE.md) when component or data boundaries change, and this workflow when verification or release steps change. Keep [README](../README.md) concise and update [AGENTS.md](../AGENTS.md) only when its project-wide rules or document map changes.

For documentation-only changes, review links, commands, behavior descriptions, and evidence provenance, and run `git diff --check`. Do not turn copied historical results into new test or acceptance claims. Preserve the dated Notes MVP records as history. Maintain local plan status separately from tracked requirements/evidence, without changing the ignored-plan policy.
