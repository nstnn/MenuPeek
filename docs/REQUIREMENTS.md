# Product requirements

MenuPocket is transitioning from its local daily menu bar checklist to a desktop task window with menu bar progress. The local [desktop plan](../plan/desktop-task-management/desktop-task-management.md) defines that increment; the TASK-001 lifecycle shell and TASK-002 daily-state boundary are implemented so far. The approved Notes MVP design is recorded in the local [Notes MVP plan](../plan/mvp/NOTES_MVP_PLAN.md). This tracked document states the product contract and distinguishes current code from the remaining transition work.

## Approved Notes MVP

- Show only notes assigned to the current local calendar day. Do not carry unfinished notes forward. Show a separate, informational count of yesterday's unfinished notes when it is nonzero.
- Show today's date and completed/total progress together. Keep incomplete notes ahead of completed notes, newest first within each group.
- Add, complete, edit, and delete notes. Trim input and reject whitespace-only text. Confirm deletion. Keep an unsaved draft and show an inline error when a write fails.
- Persist notes in one local SQLite database in the app's Application Support directory. Keep preferences separate in `UserDefaults`; preserve existing data and reject unsupported newer schemas without overwriting them.
- Keep a compact, scrollable panel with Settings access. Use English visible and accessibility copy, an icon-only menu bar label, and no demo controls in the final notes interface.
- Retain Settings, launch-at-login, and a normal way to quit the app. Keep macOS 14+, App Sandbox, and no network or third-party dependencies.
- Verify the running interface on macOS, including light and dark appearance, keyboard access, persistence across relaunch, day changes, and failure states.

History browsing, automatic carryover, reminders, recurring items, accounts, and sync are outside this MVP.

## Current implementation

The app now has Dock presence and one reusable task-window shell. The native icon-only menu bar button and Dock reopen show/restore that window, including with Settings open. Closing all windows keeps the app running. The shell has Settings access but does not yet expose task CRUD or progress; the desktop layout and status count remain pending.

The former `DailyNotesPanel` and its CRUD implementation remain in source/tests but are no longer reachable from the menu bar. `DailyNotesState` now refreshes independently on calendar-day, clock, time-zone, and wake notifications, distinguishes unavailable progress from an empty day, and retains stale edit text for recovery. SQLite storage remains unchanged, saved day assignments remain intact, and writes publish only after repository success. Startup/window refresh entry points are available; connecting them to app lifecycle and presenting recovery notices remain later desktop cards. Manual/login launch policy and first-launch Settings replacement remain pending TASK-007.

Settings now shows Launch at Login, app information, and Quit in English. The notes panel has no Quit control by design. The demo loading and preference code remains in the project, though the current app launch does not start demo loads.

The Debug build and all 86 hosted tests passed on 2026-09-27; see the [dated regression record](NOTES_MVP_REGRESSION.md). Running-app visual, accessibility, and Release acceptance remain separate checks; see [Workflow](WORKFLOW.md).
