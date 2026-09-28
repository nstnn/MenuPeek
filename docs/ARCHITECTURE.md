# Architecture

MenuPocket is a Swift 6 macOS application using SwiftUI for hosted views, AppKit for lifecycle and the retained Settings window, Foundation for state, and system SQLite for notes. The project has one app target and a hosted `MenuPocketTests` target in the shared Xcode scheme. It is sandboxed and configured as a regular Dock-visible app in Debug and Release.

## App composition

`MenuPocketApp` runs `NSApplication` with a retained `AppDelegate`; no SwiftUI scene independently creates windows. `AppDelegate` owns one `DailyNotesState`, the older demo-oriented `AppModel`, a lazy `TaskWindowController`, a retained `TaskStatusItemController`, and one reusable `SettingsWindowController`.

The desktop transition currently implements only the lifecycle shell (TASK-001). `showTasks()` reuses the same SwiftUI-hosting AppKit window, restores minimization, activates the app, and brings it forward. Dock reopen and the native icon-only status button call that boundary, even when Settings is visible. Closing all windows leaves the app running. The native application menu provides Show Tasks, Settings, Close, and Quit; termination removes the status item.

The shell receives the same daily state but does not yet render or edit tasks. The former compact Notes view remains in source and tests; it is no longer the app's menu bar surface. Today layout, progress rendering/refresh, complete commands, and manual/login launch policy belong to subsequent desktop cards. Existing first-launch Settings/onboarding behavior is retained until TASK-007.

Settings continues to receive `AppModel` for launch-at-login status and preference warnings. No persistence, identity, or login registration changes are introduced by the shell.

## Notes flow

`NoteDay` derives today and yesterday from an injectable Gregorian calendar and clock. A note keeps the local day key assigned at creation; creation and completion times are absolute instants. `NoteOrder` places incomplete notes first and uses creation time, then ID, for stable order.

`DailyNotesState` is the main-actor observable owner of the displayed daily snapshot, drafts, and errors. Panel open and calendar-day notification trigger reads. The state asks a `NoteRepository` for today's rows and yesterday's unfinished count. Add, completion, edit, and delete operations update the displayed notes only after a successful repository write. A failed read does not publish a partial snapshot; a failed add or edit retains the draft.

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
