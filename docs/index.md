# MenuPocket documentation

MenuPocket is a small, native macOS menu bar application for displaying
deterministic content modules. The first version is deliberately local and
self-contained: it uses demo data to validate the menu bar, panel, Settings,
preferences, loading states, and launch-at-login experience before any real
service integration is selected.

> The repository directory is named `MenuPeek`. The Xcode project, application
> target, bundle, and product are named `MenuPocket`.

## Quick links

| Need | Start here |
| --- | --- |
| Run the app quickly | [Quick start](#quick-start) |
| Understand the user experience | [Using MenuPocket](#using-menupocket) |
| Build and test | [Development workflow](#development-workflow) |
| Understand the implementation | [Architecture](#architecture) |
| Add a future content source | [Extending MenuPocket](#extending-menupocket) |
| Review acceptance status | [Verification and handoff](#verification-and-handoff) |
| Read the product scope | [Scope and limitations](#scope-and-limitations) |

## At a glance

| Property | Value |
| --- | --- |
| Platform | macOS 14.0 or later |
| Initial acceptance architecture | Apple Silicon |
| Language | Swift 6 |
| UI | SwiftUI with AppKit lifecycle/window integration |
| Menu bar surface | SwiftUI `MenuBarExtra` using `.window` style |
| State model | Main-actor `@Observable` `AppModel` |
| Preferences | Codable value stored in namespaced `UserDefaults` data |
| Login item | `SMAppService.mainApp`, off by default |
| Tests | XCTest in the `MenuPocketTests` target |
| Dependencies | None beyond Apple platform frameworks |
| Distribution | Local `.app` for personal use |

## Product overview

MenuPocket puts one item in the macOS menu bar. The item can show an icon and a
short value from a pinned module, or use icon-only mode. Clicking it opens a
panel containing the enabled modules in the user's chosen order.

The first version includes two deterministic demo modules:

- **Công việc mẫu** — displays `3 việc` and uses `Demo: 3 việc` as its compact
  menu bar value.
- **Trạng thái mẫu** — displays `Sẵn sàng` and uses `Demo: OK` as its compact
  menu bar value.

The product goal is to validate the shell and state transitions before adding a
real content source. Demo data is processed locally and does not require a
network connection, account, token, or external service.

## Quick start

### Requirements

You need:

- macOS 14.0 or later;
- Xcode with its command-line tools selected; and
- an Apple Silicon Mac for the initial acceptance path.

The project has no third-party packages and does not require a paid Apple
Developer membership for local ad-hoc signing. If Xcode is not selected, choose
the installed developer directory:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Open and launch a Debug build

From the repository directory:

```bash
open MenuPocket.xcodeproj
./run.sh
```

`run.sh` builds the Debug configuration using the shared `MenuPocket` scheme,
stops only the app instance at this checkout's Debug path, and opens that app.
MenuPocket is an accessory/menu bar app, so it does not appear as a normal Dock
application. Look for its grid icon in the menu bar.

Build output is placed in the ignored `build/DerivedData` directory. The script
is a local convenience launcher; it is not a packaging or distribution script.

## Using MenuPocket

### The menu bar panel

Click the MenuPocket item to open the panel. The panel contains:

1. A MenuPocket header and a visible `DEMO` indicator.
2. One row for each enabled module, in the saved order.
3. A footer with Settings, Refresh, and Quit actions.

Each module row explains its current state:

- loading data;
- displaying a successful snapshot and its local-load timestamp;
- refreshing while retaining the previous snapshot;
- displaying an empty response;
- displaying an initial failure with Retry; or
- displaying stale data with a warning and Retry after a failed refresh.

When every module is disabled, the panel explains that content can be selected
in Settings. Refresh is disabled in that state, but Settings remains available.

The panel is designed to be compact for normal content and to use a native
scrolling region when content overflows. Its implementation target is 360 pt
wide with a 480 pt maximum height.

### Settings

Settings is one retained, reusable AppKit window hosting SwiftUI content. Closing
it hides the window without quitting MenuPocket. Opening it again, reopening the
application from Finder, or using the panel's Settings action brings the same
window forward rather than creating duplicates.

The three tabs are:

#### Nội dung

The Content tab controls product preferences immediately—there is no Save
button.

- Toggle each module on or off.
- Move modules up or down within the catalog order.
- Choose `Không ghim` or an enabled pinnable module for the menu bar.
- Choose `Chỉ biểu tượng` or `Biểu tượng và thông tin`.

Disabling the pinned module clears the pin instead of silently selecting a new
one. Reordering changes position, not module identity.

#### Chung

The General tab shows the application name and version, the local-demo
explanation, and the `Mở khi đăng nhập` control. The login-item UI reflects the
system status rather than assuming that a requested operation succeeded.

Possible states include disabled, enabled, approval required, and unavailable.
When approval is required, the app provides a route to macOS Login Items
settings. The control is off by default and does not register the app merely
because Settings was opened.

#### Demo

The Demo tab provides an independent scenario picker for every module and a
button to reload enabled demo data. Scenarios are session-only and return to
`Bình thường` after the application is relaunched.

### Demo scenarios

| Scenario | Behavior |
| --- | --- |
| `Bình thường` | Returns the module's deterministic snapshot immediately. |
| `Không có dữ liệu` | Returns a completed empty response, not an error. |
| `Lỗi` | Produces a controlled provider failure. |
| `Phản hồi chậm` | Waits for the intentional two-second fixture delay while remaining cancellable. |

The slow scenario exists to make responsiveness, cancellation, and stale-result
behavior observable. It is not a polling loop or a background refresh service.

## Preferences and lifecycle behavior

The persisted preference value contains:

- schema version;
- module order;
- enabled module IDs;
- the pinned module ID; and
- menu bar display mode.

Preferences are stored under the product's namespaced `UserDefaults` key and
encoded as a Codable value. The onboarding-completed marker is separate from
the product preference value, so recovering corrupt preferences does not reopen
first-launch Settings.

On load, the preference store reconciles stored IDs with the current catalog:

- removed IDs are ignored;
- known order is preserved;
- new catalog IDs are appended;
- invalid, disabled, or unpinnable pins are cleared; and
- unrelated `UserDefaults` keys are preserved.

If stored data is corrupt, MenuPocket uses session defaults and shows a warning
without deleting the corrupt bytes. If the stored schema is newer than the
supported schema, the app preserves it byte-for-byte and disables preference
editing for that session rather than overwriting data it does not understand.

The app loads enabled modules at startup. Opening the panel is a fallback only
for enabled modules that have never completed an attempt. Explicit Refresh,
Retry, scenario changes, enablement changes, and lifecycle termination use
bounded, coordinator-owned tasks. A newer request supersedes an older request;
late results cannot overwrite current state, and cancellation is not presented
as a user-facing error.

## Development workflow

### Project layout

| Path | Responsibility |
| --- | --- |
| [`MenuPocket/App/MenuPocketApp.swift`](../MenuPocket/App/MenuPocketApp.swift) | SwiftUI app entry point and menu bar scene |
| [`MenuPocket/App/AppDelegate.swift`](../MenuPocket/App/AppDelegate.swift) | Lifecycle, onboarding, Settings window ownership, termination |
| [`MenuPocket/App/AppModel.swift`](../MenuPocket/App/AppModel.swift) | Shared observable state, preference mutations, load coordination |
| [`MenuPocket/MenuBar/MenuPocketPanel.swift`](../MenuPocket/MenuBar/MenuPocketPanel.swift) | Panel layout, module rows, empty/error/loading states, footer actions |
| [`MenuPocket/Settings/SettingsView.swift`](../MenuPocket/Settings/SettingsView.swift) | Content, General, and Demo tabs |
| [`MenuPocket/Settings/SettingsWindowController.swift`](../MenuPocket/Settings/SettingsWindowController.swift) | Retained AppKit Settings window |
| [`MenuPocket/Modules/ModuleDescriptor.swift`](../MenuPocket/Modules/ModuleDescriptor.swift) | Stable module identities and catalog |
| [`MenuPocket/Modules/ModuleProvider.swift`](../MenuPocket/Modules/ModuleProvider.swift) | Snapshot and provider boundary |
| [`MenuPocket/Modules/DemoModuleProviders.swift`](../MenuPocket/Modules/DemoModuleProviders.swift) | Deterministic demo scenarios and providers |
| [`MenuPocket/Modules/AppPreferences.swift`](../MenuPocket/Modules/AppPreferences.swift) | Codable persisted preference value |
| [`MenuPocket/Services/PreferencesStore.swift`](../MenuPocket/Services/PreferencesStore.swift) | Persistence, recovery, reconciliation, schema protection |
| [`MenuPocket/Services/LoginItemService.swift`](../MenuPocket/Services/LoginItemService.swift) | `SMAppService` boundary and truthful status mapping |
| [`Tests/MenuPocketTests/`](../Tests/MenuPocketTests/) | Hosted XCTest behavior coverage |
| [`run.sh`](../run.sh) | Local Debug build-and-launch convenience script |

### Command-line builds

Run these commands from the project directory:

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
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test

xcodebuild \
  -project MenuPocket.xcodeproj \
  -scheme MenuPocket \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

The shared scheme is [`MenuPocket.xcscheme`](../MenuPocket.xcodeproj/xcshareddata/xcschemes/MenuPocket.xcscheme).
The project contains the `MenuPocket` application target and the hosted
`MenuPocketTests` unit-test target.

The tests use injected clocks, delays, stores, providers, and login-item fakes.
They should never register or unregister the real host login item. Historical
Task 23 evidence records 65 tests with zero failures; this documentation update
does not rerun them.

### Release inspection

After a successful Release build, inspect the local artifact without adding it
to source control:

```bash
plutil -p build/DerivedData/Build/Products/Release/MenuPocket.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 \
  build/DerivedData/Build/Products/Release/MenuPocket.app
codesign --display --entitlements - --xml \
  build/DerivedData/Build/Products/Release/MenuPocket.app
shasum -a 256 \
  build/DerivedData/Build/Products/Release/MenuPocket.app/Contents/MacOS/MenuPocket
```

The expected local metadata is bundle identifier `local.menupocket.app`,
version `0.1.0 (1)`, minimum system macOS 14.0, and `LSUIElement = true`.
The artifact is not a Developer ID, notarized, App Store, or public release
package.

### Install a personal build

For login-item verification, use a stable copy rather than a temporary
DerivedData path. Quit other MenuPocket copies first and preserve any existing
application until replacement is intentional:

```bash
mkdir -p ~/Applications
cp -R build/DerivedData/Build/Products/Release/MenuPocket.app \
  ~/Applications/MenuPocket.app
```

Run the installed copy, enable `Mở khi đăng nhập` only when desired, inspect
macOS System Settings if approval is requested, and return to the app so it can
reread the state. A successful registration check is not the same as observing
the app appear automatically at a later login.

## Architecture

### Application composition

`MenuPocketApp` creates one `.window`-style `MenuBarExtra`. Its label is derived
from `AppModel.menuBarPresentation`, so the menu bar and panel read the same
observable state. `AppDelegate` supplies the model and retains one
`SettingsWindowController` for the lifetime of the process.

### State ownership and data flow

The main-actor `AppModel` owns:

- recovered and editable `AppPreferences`;
- preference warnings and save policy;
- module runtime states;
- session-only demo scenarios;
- login-item status and operation failures; and
- the current load task for each module.

The view layer reads that model. User actions call model methods, and the model
persists a candidate preference before publishing it. Providers return
`ModuleSnapshot` values; they do not own views, windows, or application state.

### Loading and cancellation

Each module has at most one authoritative current request. Starting a new load
cancels the previous task and assigns a request ID. Completion is accepted only
if the request is still current, the module is still enabled, and the app is not
terminating. This protects against non-cooperative providers that return a late
value after cancellation.

### Login-item boundary

The app wraps `SMAppService.mainApp` behind `LoginItemService`. The production
service rereads the system status after registration or unregistration and maps
approval-required, unavailable, and failure cases to explicit UI states. Tests
replace the system boundary with fakes, keeping unit tests from mutating the
host Mac.

## Extending MenuPocket

Real content should be added only after the source and its permissions are
selected. The extension sequence is:

1. Add a new stable `ModuleDescriptor.ID` and descriptor to the catalog.
2. Implement a `ModuleProvider` for the source.
3. Convert source data into the existing `ModuleSnapshot` shape.
4. Register the provider with the model.
5. Add source-specific Settings only when the source needs them.
6. Define error, permission, and refresh behavior for that source.
7. Add provider and integration tests for success, empty, failure, and relevant
   cancellation or permission cases.

Do not add `URLSession`, Keychain, timeout/retry policies, caching, scheduled
background refresh, protected system-data access, a database, or a backend just
because a future integration might need it. Each belongs to the selected source
and should arrive with the source-specific requirements.

## Verification and handoff

The point-in-time handoff report is [`plan/task-030/report.md`](../plan/task-030/report.md).
It records the Release artifact path and hash, the accepted assumption that
TASK-026 through TASK-029 are complete, and the fact that those checks were not
rerun during the documentation handoff.

The evidence rules are deliberately strict:

- A successful compile proves compilation, not runtime behavior.
- Passing XCTest proves the tested model behavior, not menu bar interaction.
- Settings accessibility evidence does not prove that the
  SystemUIServer-owned menu bar panel was reachable.
- A Release bundle hash proves artifact identity, not that the artifact launched
  in every environment.
- Login-item registration is separate from verified startup at a later login.
- A missing hardware or UI condition is `Not tested`, not an inferred pass.

The final source, artifact identity, test result, UI observations, performance
measurements, login-item evidence, and limitations must be kept together when
making a release or acceptance claim. Rebuilding after a source change makes
earlier Release/UI/performance/login evidence stale.

## Current handoff status

The documentation handoff was prepared on the user's instruction to accept
TASK-026, TASK-027, TASK-028, and TASK-029 without repeating their checks. The
following statements describe the handoff record, not fresh execution of this
page:

| Area | Handoff status |
| --- | --- |
| Project source, Xcode project, shared scheme, and tests | Present in the repository |
| Debug and Release builds | Accepted by assumption; not rerun for the handoff |
| Behavior tests | Accepted by assumption; not rerun for the handoff |
| Display, window, and repeated-panel checks | Accepted by assumption; not rerun for the handoff |
| Installed-app login controls | Accepted by assumption; not rerun for the handoff |
| Next real login | Accepted by assumption; not rerun for the handoff |
| Documentation self-check | Not run |

If the next-login observation was not actually completed, the final acceptance
status must say: **launch-at-login acceptance is incomplete**.

## Scope and limitations

MenuPocket v1 is a personal local demo shell. It intentionally excludes:

- external service APIs;
- authentication, OAuth, and token storage;
- notes, task lists, and timers as product features;
- AI, a backend, cloud synchronization, and telemetry;
- downloadable plugins and execution of user scripts;
- global keyboard shortcuts and notifications;
- multiple independent menu bar items;
- automatic updates;
- App Store distribution, Developer ID signing, and notarization; and
- usage tracking or external crash reporting.

Build products, Xcode user-specific state, and personal signing material should
remain outside source control.

## Troubleshooting

### The app does not appear in the Dock

That is expected. MenuPocket is configured as an accessory/menu bar app. Look
for the grid icon in the system menu bar.

### Xcode is not selected

Check the selected developer directory with `xcode-select -p` and select the
installed Xcode path if necessary. Then rerun the build command.

### The menu bar value is icon-only

Open Settings → `Nội dung` and choose `Biểu tượng và thông tin`. A value is only
shown when an enabled pinnable module is selected and the display mode permits
it.

### A module does not appear in the panel

Check its Content switch and the saved module order. If all switches are off,
the panel intentionally shows guidance instead of rows.

### Settings opens on first launch but not later

That is the intended onboarding behavior. The first-launch General tab is
controlled by a separate onboarding marker; subsequent launches restore
preferences without reopening Settings automatically.

### Login-item state is unavailable

The app must reflect an unavailable or approval-required system state instead of
claiming that registration succeeded. Use the displayed Login Items action when
macOS asks for approval, then return to Settings to reread the state.

## Project documents

- [`README.md`](../README.md) — concise repository and quick-start guide.
- [`plan/task-030/report.md`](../plan/task-030/report.md) — point-in-time Task 30
  handoff and evidence boundaries, when the local planning artifacts are
  present.

The implementation plan and master roadmap are planning artifacts rather than
runtime dependencies. They may be absent from a fresh product checkout; this
page keeps the user-facing product and development guidance self-contained.
