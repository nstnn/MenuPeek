# Product requirements

MenuPocket is one local macOS desktop and menu bar app for daily tasks. The desktop increment replaces the compact editable popup with a reusable Today window and menu bar progress. This tracked document defines the product contract without requiring the Git-ignored local plan.

The behavior below is implemented in source. Dated verification results belong in [Desktop regression](DESKTOP_TASK_REGRESSION.md) and [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md); implementation, automated verification, and actual system observations are separate claims.

## Desktop task contract

| Requirement | Expected behavior |
| --- | --- |
| REQ-001 — Task window | One resizable task window is reachable from the menu bar and Dock. Repeated presentation restores the same window after closing or minimizing it, including while Settings is open. |
| REQ-002 — Menu bar progress | The saved completed/total count stays visible in the menu bar without an icon while running. A successful empty read shows `0/0`; initial or failed reads show `—`. Successful writes update progress without opening the window; rejected writes retain the last saved count. |
| REQ-003 — Today layout | Show the current local date, progress, tasks, Add task, Settings access, and an informational yesterday count when nonzero. Highlight the yesterday reminder in semibold red so unfinished planned tasks are easy to notice. Incomplete tasks precede completed tasks, newest first within each group. Keep empty, all-completed, long-list, long-text, and resized states usable. |
| REQ-004 — Task actions | Add, complete, uncomplete, edit, and delete tasks. Trim input and reject whitespace-only text. Confirm deletion with cancellation available. Publish saved changes only after a successful write; failures retain saved rows/count and recoverable draft text with an inline error. |
| REQ-005 — Daily model | Keep each task's assigned local day. Do not carry unfinished tasks into today. Refresh both surfaces on day, clock, time-zone, and wake changes without requiring an open task window. Yesterday's unfinished count is informational. |
| REQ-006 — Lifecycle | Explicit launch, Dock reopening, and a primary menu bar click show tasks. The app remains in the Dock and Command-Tab. Closing the last window leaves the process and status item running; Quit exits and removes the item. |
| REQ-007 — Login startup | Preserve the existing launch-at-login registration and Settings control. Login launch initializes daily progress without raising task or Settings windows or requesting activation; the Dock icon remains visible. A genuine login requires separate system observation. |
| REQ-008 — Native interaction | Settings is reachable from the task window and native menu. Support keyboard focus, Return to save, Escape to cancel, Command-N to add, Command-comma for Settings, Command-W to close, Command-Q to quit, and native text editing. Clicking noninteractive space in the Today window clears the visible control focus; Tab can focus a control again. |
| REQ-009 — Preservation | Keep existing SQLite tasks, preferences, onboarding state, app identity, and sandbox storage. This increment introduces no data migration. Reject unsupported newer schemas without overwriting their data. |
| REQ-010 — Acceptance | Record automated build/test results separately from actual running-app menu bar, Dock, window, Settings, and system observations. Identify the final source and artifact. Record unavailable checks accurately. |
| REQ-011 — Handoff | Current product/developer docs agree about behavior, scope, implementation, and verification status. Tracked evidence remains understandable without local ignored plans or build artifacts. |

## Interaction and recovery rules

Add and edit use single-line fields. Return/Save stores valid trimmed text; Escape/Cancel discards the relevant draft. Completing or uncompleting a task changes saved ordering and progress only after persistence succeeds. Completed tasks remain visible with muted presentation.

New and current-day edit drafts survive task-window close/reopen within the running process. Add and other row actions cannot replace an active edit. Command-N is unavailable during editing, deletion confirmation, or unavailable data. Quit/relaunch preserves saved tasks but does not promise unsaved-draft recovery.

Deletion uses inline confirmation with Cancel initially focused. Cancel/Escape, window close, unavailable data, a changed day, or a removed target cancels confirmation. Confirmation is consumed before writing; a failed delete keeps the row/count and requires fresh confirmation for retry.

A day change cancels stale edit/deletion targets with an explanation and preserves unsaved edit text for recovery. Recovery text is selectable and never saved automatically to another task or day. A new task receives its day assignment when explicitly saved. Retry rereads through the shared daily state.

All app-owned visible and accessibility copy is English, including dates independently of the Mac's language. User-entered text is preserved as entered. Settings provides Open at Login, app information, and Quit. First explicit presentation completes unfinished onboarding; quiet login startup does not. Existing onboarding completion is preserved.

## Storage and platform constraints

- Preserve bundle identifier `local.menupocket.app`, SQLite schema version 1, and the sandbox's Application Support `MenuPocket/notes.sqlite`.
- Keep preferences and onboarding markers in their existing `UserDefaults` storage, separate from tasks.
- Retain macOS 14+, SwiftUI/AppKit, App Sandbox, system SQLite, and no account, network service, or third-party dependency.
- Use one app-owned daily state and repository connection. Window presentation and menu bar rendering are consumers, not additional saved-data authorities.
- Verify with the shared `MenuPocket` scheme and isolated fixtures/fakes. Do not seed scenarios by changing the user's tasks or real login registration.

## Scope exclusions

Future-day planning, history browsing, automatic carryover, projects, tags, priorities, deadlines, reminders, recurring tasks, search, filters, sync, accounts, multiple task windows, a second editable menu bar checklist, and a separate background helper remain outside this increment.

Renaming stored `Note` types/tables, unrelated legacy-demo cleanup, saved-task undo/redo, durable unsaved drafts across Quit, public distribution, notarization, and App Store release are also excluded. Native text undo/redo remains supported.

## Implementation and acceptance status

The task window, CRUD/recovery rules, shared progress, closed-window refresh, native commands, manual/login launch classification, and preservation boundaries are implemented. Task 8's 2026-09-29 regression and local artifact results are retained in the [tracked regression record](DESKTOP_TASK_REGRESSION.md).

Task 9's actual Release report records partial acceptance: window/text/cancellation/Settings/Quit and observed-row relaunch checks passed, while menu bar/Dock and safe-fixture access were blocked and several layout/system checks were not tested. [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md) retains those scoped results and the exact remaining gate. Full feature acceptance remains open until the material observations pass against the final artifact.

## Historical Notes MVP

The earlier MVP used an icon-only `MenuBarExtra` and compact daily checklist. Its daily ordering, CRUD, failure recovery, SQLite preservation, English copy, Settings, and local-only scope remain the baseline. The desktop task contract supersedes its compact-panel, icon-only label, and Settings-first explicit-launch presentation.

The original [Notes MVP regression](NOTES_MVP_REGRESSION.md) and [Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) retain their dated results and automation limitations. They do not establish acceptance of the desktop window or native status item. Detailed local plans are linked from the [documentation index](index.md).
