# Architecture

MenuPocket is a Swift 6 macOS application using SwiftUI for its menu bar scene and views, AppKit for lifecycle and the retained Settings window, Foundation for state, and system SQLite for notes. The project has one app target and a hosted `MenuPocketTests` target in the shared Xcode scheme. It is sandboxed and configured as an accessory app without a Dock icon.

## App composition

`MenuPocketApp` creates a `.window` style `MenuBarExtra`. `AppDelegate` owns a `DailyNotesState`, the older demo-oriented `AppModel`, and one `SettingsWindowController`. The current menu bar panel receives `DailyNotesState`; the Settings window still receives `AppModel`. The app creates the Settings window on first launch through a separate onboarding marker, and reuses that window afterward.

## Notes flow

`NoteDay` derives today and yesterday from an injectable Gregorian calendar and clock. A note keeps the local day key assigned at creation; creation and completion times are absolute instants. `NoteOrder` places incomplete notes first and uses creation time, then ID, for stable order.

`DailyNotesState` is the main-actor observable owner of the displayed daily snapshot, drafts, and errors. Panel open and calendar-day notification trigger reads. The state asks a `NoteRepository` for today's rows and yesterday's unfinished count. Add, completion, edit, and delete operations update the displayed notes only after a successful repository write. A failed read does not publish a partial snapshot; a failed add or edit retains the draft.

`SQLiteNoteRepository` opens one database at `Application Support/MenuPocket/notes.sqlite` within the app's sandbox container. The database has a versioned `notes` table and day-key index. A newer unknown schema is rejected without rewriting it. The repository interface lets tests inject a fake or a temporary SQLite database. There is no account, network service, or synchronization path.

## Remaining demo and system boundaries

`AppModel`, `ModuleCatalog`, demo providers, `AppPreferences`, and `PreferencesStore` still support the older Settings surface. Product preferences use a namespaced `UserDefaults` value with reconciliation and newer-schema write protection; they are distinct from the SQLite notes database. Demo providers are no longer started on app launch.

`LoginItemService` wraps `SMAppService.mainApp`. Settings rereads system status and reports disabled, enabled, approval-required, and unavailable states. Tests inject a fake service so they do not register or unregister the host Mac's real login item. Release and login-item verification need an installed copy at a stable location; registration alone does not prove startup at the next login.

## Source map

| Area | Main files |
| --- | --- |
| App lifecycle and menu bar | `MenuPocket/App/MenuPocketApp.swift`, `AppDelegate.swift` |
| Notes domain, state, UI, and storage | `MenuPocket/Notes/` |
| Settings and login item | `MenuPocket/Settings/`, `MenuPocket/Services/LoginItemService.swift` |
| Legacy demo and preferences | `MenuPocket/Modules/`, `MenuPocket/App/AppModel.swift`, `MenuPocket/Services/PreferencesStore.swift` |
| Behavior tests | `Tests/MenuPocketTests/` |
