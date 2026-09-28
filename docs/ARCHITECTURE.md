# Architecture

MenuPocket is a Swift 6 macOS application using SwiftUI for hosted views, AppKit for lifecycle and the retained Settings window, Foundation for state, and system SQLite for notes. The project has one app target and a hosted `MenuPocketTests` target in the shared Xcode scheme. It is sandboxed and configured as a regular Dock-visible app in Debug and Release.

## App composition

`MenuPocketApp` runs `NSApplication` with a retained `AppDelegate`; no SwiftUI scene independently creates windows. `AppDelegate` owns one `DailyNotesState`, the older demo-oriented `AppModel`, a lazy `TaskWindowController`, a retained `TaskStatusItemController`, and one reusable `SettingsWindowController`.

The desktop transition currently implements the lifecycle shell (TASK-001), independent daily-state boundary (TASK-002), and Today layout (TASK-003). `showTasks()` reuses the same SwiftUI-hosting AppKit window, refreshes saved daily state, restores minimization, activates the app, and brings it forward. Dock reopen and the native icon-only status button call that boundary, even when Settings is visible. Closing all windows leaves the app running. The native application menu provides Show Tasks, Settings, Close, and Quit; termination removes the status item.

`TaskWindowController` hosts `TaskWindowView` with the app-owned daily state. The view reads `availableProgress` before deciding whether to show saved rows, a valid empty state, or an unavailable state with Retry. The header and action area remain outside the flexible scroll view; rows wrap long text and preserve the state-owned ordering. It displays refresh notices and selectable recovery text. Add task has an optional action boundary and remains disabled until TASK-004 connects it; rows currently display completion without mutating it. The former compact Notes view remains in source and tests; it is no longer the app's menu bar surface. CRUD, menu bar progress, startup refresh, complete commands, and manual/login launch policy belong to subsequent desktop cards. Existing first-launch Settings/onboarding behavior is retained until TASK-007.

Settings continues to receive `AppModel` for launch-at-login status and preference warnings. No persistence, identity, or login registration changes are introduced by the desktop layout.

## Notes flow

`NoteDay` derives today and yesterday from an injectable Gregorian calendar and clock. Its default path rebuilds a Gregorian calendar using the current system time zone for each calculation; an explicitly injected calendar stays fixed. One `keys()` call uses the same instant and calendar for both days. A note keeps the local day key assigned at creation; creation and completion times are absolute instants. `NoteOrder` places incomplete notes first and uses creation time, then ID, for stable order.

`DailyNotesState` is the main-actor observable owner of the displayed daily snapshot, drafts, and errors. State-owned observers trigger reads on calendar-day, system-clock, time-zone, and workspace wake notifications, even with no window open; they are removed when state is released. The task-window controller calls `windowWillOpen()` on every explicit presentation; `startup()` wiring remains TASK-007. The state asks a `NoteRepository` for today's rows and yesterday's unfinished count. Add, completion, edit, and delete operations update the displayed notes only after a successful repository write. A failed read does not publish a partial snapshot; a failed add or edit retains the draft.

Consumers use `availableProgress` to distinguish an initial/failed read (`nil`, rendered as `—` by the Today view and later TASK-006) from a successful empty read (`0/0`). `hasLoadedToday` becomes false on every failed read, including a same-day refresh; same-day cached rows remain available for recovery but are not an available count. Failed writes retain the last saved rows and available count. Both Today rows and yesterday's informational count must load successfully before publishing a snapshot.

A changed day clears the old snapshot before reading the new day and never reassigns stored day keys. Existing-row actions that discover a rollover refresh and return false; stale IDs cannot mutate yesterday's rows. Refresh cancels an edit whose day changed or target disappeared, retaining its text in `recoveredEditDraft` and exposing `refreshNotice`. Same-day window refresh preserves a valid active edit. The new-task `draft` remains independent and is assigned to the then-current day only on explicit save. The Today view presents recovery text/notices; TASK-005 must clear local deletion confirmation when the day or target changes; state guards remain the final protection against stale deletion. Recovery text is session-only and is never automatically saved as a new task.

`DailyNotesView` keeps deletion confirmation inside the menu bar panel, avoiding a separate alert that can take focus from the transient `MenuBarExtra` window. Cancel, Escape, or closing the panel clears the pending confirmation. Confirming clears it before requesting the repository write; a failed deletion leaves the saved note visible with an inline error.

`SQLiteNoteRepository` opens one database at `Application Support/MenuPocket/notes.sqlite` within the app's sandbox container. The database has a versioned `notes` table and day-key index. A newer unknown schema is rejected without rewriting it. The repository interface lets tests inject a fake or a temporary SQLite database. There is no account, network service, or synchronization path.

## Remaining demo and system boundaries

`AppModel`, `ModuleCatalog`, demo providers, `AppPreferences`, and `PreferencesStore` retain earlier demo behavior, but it is not exposed in Settings. Product preferences use a namespaced `UserDefaults` value with reconciliation and newer-schema write protection; they are distinct from the SQLite notes database. Demo providers are no longer started on app launch.

`LoginItemService` wraps `SMAppService.mainApp`. Settings rereads system status and reports disabled, enabled, approval-required, and unavailable states. Tests inject a fake service so they do not register or unregister the host Mac's real login item. Release and login-item verification need an installed copy at a stable location; registration alone does not prove startup at the next login.

## Source map

| Area | Main files |
| --- | --- |
| App lifecycle and menu bar | `MenuPocket/App/MenuPocketApp.swift`, `AppDelegate.swift` |
| Notes domain, state, UI, and storage | `MenuPocket/Notes/` |
| Settings and login item | `MenuPocket/Settings/`, `MenuPocket/Services/LoginItemService.swift` |
| Legacy demo and preferences | `MenuPocket/Modules/`, `MenuPocket/App/AppModel.swift`, `MenuPocket/Services/PreferencesStore.swift` |
| Behavior tests | `Tests/MenuPocketTests/` |
