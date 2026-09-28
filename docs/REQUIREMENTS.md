# Product requirements

MenuPocket is transitioning from its local daily menu bar checklist to a desktop task window with menu bar progress. The local [desktop plan](../plan/desktop-task-management/desktop-task-management.md) defines that increment; the TASK-001 lifecycle shell, TASK-002 daily-state boundary, and TASK-003 Today layout are implemented so far. The approved Notes MVP design is recorded in the local [Notes MVP plan](../plan/mvp/NOTES_MVP_PLAN.md). This tracked document states the product contract and distinguishes current code from the remaining transition work.

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

The app now has Dock presence and one reusable task window. The native icon-only menu bar button and Dock reopen show/restore that window, including with Settings open. Closing all windows keeps the app running. The resizable Today view shows the local date, saved completed/total progress, ordered tasks, an informational yesterday count, and Settings access. Successful empty reads show `0/0` and `No tasks yet`; unavailable reads show `—` and Retry. Long task text wraps and the list scrolls independently of the header and primary actions. Completed rows remain visible and muted. Add task is visible but disabled until TASK-004; row completion and CRUD interactions remain TASK-004/005. The menu bar count remains TASK-006.

The former `DailyNotesPanel` and its CRUD implementation remain in source/tests but are no longer reachable from the menu bar. `DailyNotesState` refreshes independently on calendar-day, clock, time-zone, and wake notifications, distinguishes unavailable progress from an empty day, and retains stale edit text for recovery. Each explicit task-window presentation refreshes the same shared state; Retry reads through that state too. The Today view displays refresh notices and selectable recovered edit text without automatically saving it. SQLite storage remains unchanged, saved day assignments remain intact, and writes publish only after repository success. Startup refresh, manual/login launch policy, complete commands, and first-launch Settings replacement remain pending TASK-007.

TASK-003 layout checks cover the actual Debug app's empty state and Settings route plus an isolated in-memory fixture window for sizing, mixed/all-completed/long-list/long-text states, unavailable-read retry, recovery text, and light/dark focus treatment. These do not close TASK-001's remaining real menu bar/Dock checks or establish integrated feature acceptance; local evidence is in the [TASK-003 record](../plan/desktop-task-management/evidence/task-003.md).

Settings now shows Launch at Login, app information, and Quit in English. The notes panel has no Quit control by design. The demo loading and preference code remains in the project, though the current app launch does not start demo loads.

The Debug build and all 86 hosted tests passed on 2026-09-27; see the [dated regression record](NOTES_MVP_REGRESSION.md). Running-app visual, accessibility, and Release acceptance remain separate checks; see [Workflow](WORKFLOW.md).
