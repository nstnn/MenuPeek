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

The hosted tests cover note day boundaries, ordering, SQLite persistence and errors, shared-state availability and refresh, repeated status-count observation, window/lifecycle/native commands, preferences, demo loading, login-item behavior, Quick Add registration, capture panel, and add path through injected fakes, and History range/day/Unfinished reads, month-grid geometry, browse state, child-screen routes, and integrated History count/preservation agreement (`TaskHistoryIntegrationTests`). Tests must not modify the Mac's real login-item registration or register a real global hotkey. `AppModel` defaults to the Carbon hotkey service, so every test that turns Quick Add on injects `FakeHotKeyService`, and service tests use a fake `HotKeySystemAccess`; constructing the Carbon service registers nothing. The Debug XCTest host skips production delegate initialization; lifecycle tests supply isolated daily repositories, defaults, launch context, and login and hotkey services. Tests that start a delegate must clean up its windows, Quick Add panel, and status item and restore native menus and the application appearance.

For a user-facing change, run the relevant tests and inspect the running app. In particular, exercise task-window opening, task writes and relaunch, empty and long lists, Command-N/W/Q/comma, native text editing, Settings reuse, and both appearances as applicable. For a theme change, check each Theme choice against the macOS appearance, including the menu bar count and a relaunch. For a Quick Add change, press Control-Option-N with another app frontmost, with the Today window or Settings key, and over a full-screen app. Check that MenuPocket does not become active, that Return saves and updates the menu bar count, that Escape, Command-W, clicking outside, and a second press discard the text, that native editing works and Command-Q/N/comma do nothing, and that a half-typed Today draft survives a capture. To check conflict reporting, register the same key from a throwaway process kept outside the repository and the app, once shared and once exclusive, and quit it between cases. For a menu bar glance change, right-click and Control-click the count and check the header on one line with its bar, the rows' order and truncation, the overflow and `Later · N remaining` lines, each action (Add Task… from an idle Later tab lands on Today; it is disabled during an edit, deletion confirmation, the category manager, or unavailable data), the Empty, All done, and Unavailable/Retry states, that Escape changes nothing and raises no window, that a primary click and a VoiceOver press still open Today after a glance (including right after a right-click), legibility with macOS in Light and in Dark (the glance follows the macOS appearance, not the Theme setting), and the VoiceOver header and "Show quick look" custom action. Check explicit launch versus quiet login startup separately, without changing real login registration to seed an automated test. Record unavailable UI or hardware checks as untested. Compilation and XCTest do not prove menu bar, Settings, or global hotkey interaction.

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

Category preferences use `local.menupocket.app.taskCategories.lastUsedCategoryID` (UUID string; absent means General) and `local.menupocket.app.taskCategories.collapsedGroupIDs` (category UUID strings plus `general`). Later uses separate `local.menupocket.app.taskCategories.later.lastUsedCategoryID` and `local.menupocket.app.taskCategories.later.collapsedGroupIDs` keys. Both scopes are separate from schema-1 `AppPreferences` and SQLite schema v3. A fixture must use an isolated defaults suite for these keys as well as existing preferences/onboarding, preserving the real user's values. Missing/deleted choices fall back safely; Quick Add saves to General without changing the remembered Today choice.

Record automated, native-fixture, production-identity, and genuine-system outcomes separately. The [category handoff](TASK_CATEGORIES_HANDOFF.md) owns the current evidence summary and remaining gate; the dated desktop records retain the detailed results. TASK-012 documentation completion does not substitute for TASK-011 interface acceptance.

## Today / Later verification

Use the shared scheme for schema v3 migration, Later repository/transfer transactions, per-list availability, Later state/drafts, scoped presentation, and native routing. For native scenarios, use the production `AppDelegate`, views, and state with an isolated SQLite database and defaults suite, an injected clock, fake login/hotkey services, and injectable read/write failures. Record the fixture's path, PID, bundle/hash, database, and defaults before changing data.

Exercise both tabs at minimum and normal size in light and dark; Later add/complete/edit/delete/cancel; Move to Today success and failure (no duplicate, both counts updated); shared category rename/removal across both tabs; drafts across tab switches and close/reopen; guards on tab switching; a Later edit across an injected day change; Command-N routing; status-item click while Later is idle and while guarded; Quick Add while Later is selected; large, empty, and all-completed lists; per-list read failure; and a changed-data quit/relaunch of the same artifact. Record automated results in [Later regression](LATER_TASKS_REGRESSION.md) and interface results in [Later acceptance](LATER_TASKS_ACCEPTANCE.md). A renamed fixture does not establish production-identity status item, Dock, global hotkey, login, or sandbox behavior.

## Schema v3 upgrade preparation

Schema v3 adds `later_tasks` to the existing file; known unversioned/v1/v2 stores upgrade in one transaction and v3 reopens without rewriting. Before the first real-data launch of a v3 build, quit every MenuPocket copy completely, then make a verified, consistent recoverable copy of the sandbox's `notes.sqlite`, for example with `sqlite3 notes.sqlite ".backup <path>"` followed by `PRAGMA integrity_check` on the copy. The app uses SQLite's default rollback journal; if a `-journal` file remains beside the database, do not copy the files by hand. Record the backup location, source schema version, and the build that will open it. Verification so far used only isolated databases; no v3 build has been launched against the user's database.

A v2 binary cannot reopen a v3 store. Do not downgrade, reset, or hand-edit the schema; restoring the pre-upgrade backup is a separate deliberate action that loses Later tasks and any other post-backup changes.

## History verification

History is read-only, so verification must show that browsing writes nothing. Hosted tests use temporary SQLite databases, isolated defaults, and injected clocks/calendars; cover Gregorian month edges (leap years, every starting weekday, year boundaries) with civil-day keys rather than 86,400-second steps.

For native checks, build a fixture from the production views/state with an isolated SQLite database and defaults suite, a fixed clock, and fake login/hotkey services; never seed History scenarios in the user's data. Seed enough earlier unfinished days to need Load more (more than 31). To exercise Retry, wrap the production repository so month, day, or Unfinished-page reads throw on demand, and record those as injected failures rather than storage faults. Verify the fixture's path, bundle, executable hash, database, and defaults suite before interacting.

Exercise the calendar entry and Back to Today in the same window; month controls, arrow keys, and cell selection; detail filters with unchanged counts; Unfinished entry, Load more, row selection, Back to Unfinished, and Go to Today; the yesterday entry; draft, composer, and scroll retention across visits, close, and minimize; Command-N, menu bar, Dock, and Show Tasks returning to Today; Command-1/Command-2 and the title-bar Today/Later control leaving History, with no History entry on Later; Settings reuse; the category-manager/edit/delete guards; each pane's Retry; Light and Dark; the 600 × 400 minimum by a real window drag (tool resizes can bypass it); and VoiceOver where available. Compare the schema, every row with its rowid, and the defaults suite before and after browsing and after a quit/relaunch; only intentional Today changes may differ. Record genuine day, wake, and time-zone changes as Not tested unless actually observed.

## Schema v2 upgrade preparation

Migration verification uses only temporary databases through the shared scheme; the Debug XCTest host does not initialize production storage. Before the first real-data launch of a v2 build, quit the app completely and prepare a verified, consistent recoverable copy of `notes.sqlite` and any relevant SQLite sidecars. Record the backup location and database/build identity. Task 2 verifies isolated migration fixtures only; it does not launch a v2 app against the user's database or prepare/restore that backup.

The upgrade keeps the existing notes table and rowids, leaves all existing tasks uncategorized (General), and preserves unrelated defaults/login state. Unsupported or incompatible schemas remain protected. A v1 binary cannot reopen v2; do not downgrade/reset the database or promise backward binary compatibility. Restoring a pre-upgrade backup is a separate deliberate action that loses post-backup changes.

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

Record automated results in [Desktop regression](DESKTOP_TASK_REGRESSION.md) and actual-interface results in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md), or in the Later records for Today/Later work. Identify the source revision and dirty inputs, configuration, toolchain, version/build, app path, executable/bundle hashes, timestamp, and running path/PID as applicable. Distinguish an installed production-identity app from fixtures using another bundle ID, database, defaults suite, or sandbox arrangement. Keep screenshots/observations tied to the artifact; a process snapshot alone does not identify which UI action succeeded.

Use Pass, Fail, Not tested, or Blocked for checks with recorded outcomes. A dependency completion assumption is not an observed result. A genuine login, day transition, display configuration, or VoiceOver check needs its own evidence; injected contexts and registration status remain supporting automated facts. Retain the essential identity and results in tracked documents even when raw logs, app bundles, or screenshots remain under ignored `build/`.

## Documentation changes

Update [Requirements](REQUIREMENTS.md) when product behavior or scope changes, [Architecture](ARCHITECTURE.md) when component or data boundaries change, and this workflow when verification or release steps change. Keep [README](../README.md) concise and update [AGENTS.md](../AGENTS.md) only when its project-wide rules or document map changes.

For documentation-only changes, review links, commands, behavior descriptions, and evidence provenance, and run `git diff --check`. Do not turn copied historical results into new test or acceptance claims. Preserve the dated Notes MVP records as history. Maintain local plan status separately from tracked requirements/evidence, without changing the ignored-plan policy.
