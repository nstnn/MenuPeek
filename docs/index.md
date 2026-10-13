# MenuPocket documentation

MenuPocket manages daily tasks in one desktop window, where Today tasks can be dragged or moved between categories, shows earlier days read-only in History, and shows saved progress in the menu bar. These tracked documents describe the current product and its verification evidence:

- [README](../README.md) — prerequisites, quick start, tests, and a short usage guide.
- [Requirements](REQUIREMENTS.md) — desktop task behavior, Today/Later scope, read-only History/Unfinished/month calendar, task movement, and acceptance criteria.
- [Architecture](ARCHITECTURE.md) — app composition, data flow, persistence, and system boundaries.
- Diagrams for new developers — [architecture](diagrams/architecture.html), [database schema](diagrams/database-schema.html), [write path](diagrams/write-path.html), [entry points](diagrams/entry-points.html), and [task window navigation](diagrams/task-window-navigation.html). Each is a self-contained HTML page; open it locally in a browser.
- [Workflow](WORKFLOW.md) — build, verification, and local Release steps.
- [Desktop regression](DESKTOP_TASK_REGRESSION.md) — dated automated regression, category storage/state/UI checks, History read/state/integration checks, task movement storage/state/routing checks and CI, local builds, and retained artifact identity.
- [Later tasks regression](LATER_TASKS_REGRESSION.md) — integrated Today/Later tests, changed-data reopen, Debug/Release identity, preservation and cleanup.
- [Later tasks acceptance](LATER_TASKS_ACCEPTANCE.md) — isolated native fixture identity and the Today/Later interface checklist; user-reported Pass on the isolated fixture, production/system checks not tested.
- [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md) — dated actual-interface observations, category, History, menu bar glance, and task movement fixtures, partial acceptance, and blocked/untested production and system checks.
- [Task categories handoff](TASK_CATEGORIES_HANDOFF.md) — category source/artifact identity, automated and interface evidence, completed documentation, and the remaining TASK-011 acceptance gate.
- [Settings shortcuts verification](SETTINGS_SHORTCUTS_VERIFICATION.md) — the read-only shortcut reference, focused tests, native Settings component evidence, keyboard/production limits, and temporary-app cleanup.

## Historical evidence

- [Notes MVP regression](NOTES_MVP_REGRESSION.md) — original 2026-09-27 compact-panel build/test evidence.
- [Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) — original compact-panel/fixture observations and system-menu-bar limitations. These results do not establish desktop acceptance.

## Local plans

The [Today / Later implementation plan](../plan/later-tasks/later-tasks.md) tracks the implemented undated Later list with text/category only and explicit Move to Today. Integrated automated verification has passed and isolated native-fixture checks are user-reported Pass; production-identity/system checks and the first real-data upgrade remain Not tested.

The [History, Unfinished, and monthly calendar plan](../plan/task-history/task-history.md) records the implemented History feature's task cards, evidence, and handoff.

The [menu bar glance plan](../plan/menu-bar-glance/menu-bar-glance.md) records the read-only right-click glance's task cards, evidence, and handoff. It is implemented, and 12 of 16 native fixture checks passed outright (Control-click only synthetically); VoiceOver, the native tooltip, Themes with macOS in Light, and a physical Control-click remain Not tested.

The [task movement plan](../plan/task-movement/task-movement.md) records saved reordering and category movement: task cards, evidence, and handoff. It is implemented and merged; automated checks and CI pass, and native fixture results are partial, with several merged-build drag scenarios, the minimum window, Light appearance, VoiceOver, and macOS 14 Not tested.

The [task-categories plan](../plan/task-categories/task-categories.md) defines the category implementation and acceptance sequence. The [desktop task-management plan](../plan/desktop-task-management/desktop-task-management.md) defines the preceding desktop increment. The earlier [Notes MVP design](../plan/mvp/NOTES_MVP_PLAN.md) and [task cards](../plan/mvp/NOTES_MVP_TASKS.md) describe the superseded compact panel. The [initial roadmap](../plan/init/master_plan.md) records the historical demo-shell phase.

`plan/` and `build/` are ignored by Git and may be absent from another checkout. Current requirements and the tracked desktop evidence records stand on their own; local links provide additional detail without changing that Git policy.

The 2026-10-08 movement follow-up closes Task 10/11 evidence handoff within the user-reduced manual scope: steps 1–7 were reported Pass on their recorded artifacts, and final SQLite confirms the cross-group moves. Remaining manual checks were skipped by user, cursor deferred, and full native/system acceptance remains unestablished. [Final session and cleanup](DESKTOP_TASK_ACCEPTANCE.md#movement-follow-up--session-closure-with-user-accepted-gaps-2026-10-08).
