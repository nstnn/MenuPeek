# Product requirements

MenuPocket's current direction is a small, local daily checklist in one macOS menu bar panel. The approved Notes MVP design is recorded in the local [Notes MVP plan](../plan/mvp/NOTES_MVP_PLAN.md). This tracked document states the product contract and distinguishes current code from the remaining transition work.

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

The menu bar opens `DailyNotesPanel` with an icon-only label. The panel shows today's notes, progress, yesterday's unfinished count, a single-line composer, completion toggles, and secondary edit/delete actions with deletion confirmation. `DailyNotesState` reads on panel open and calendar-day change; note writes are published to the UI only after the repository succeeds. The SQLite store supports add, read, completion, edit, and delete operations and refuses a newer schema version.

Settings now shows Launch at Login, app information, and Quit in English. The notes panel has no Quit control by design. The demo loading and preference code remains in the project, though the current app launch does not start demo loads.

Code and tests establish these implementation facts. Running-app visual, accessibility, and Release acceptance remain separate checks; see [Workflow](WORKFLOW.md).
