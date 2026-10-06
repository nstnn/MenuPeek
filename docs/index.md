# MenuPocket documentation

MenuPocket manages daily tasks in one desktop window, shows earlier days read-only in History, and shows saved progress in the menu bar. These tracked documents describe the current product and its verification evidence:

- [README](../README.md) — prerequisites, quick start, tests, and a short usage guide.
- [Requirements](REQUIREMENTS.md) — desktop task behavior, read-only History/Unfinished/month calendar, daily-only scope, and acceptance criteria.
- [Architecture](ARCHITECTURE.md) — app composition, data flow, persistence, and system boundaries.
- [Workflow](WORKFLOW.md) — build, verification, and local Release steps.
- [Desktop regression](DESKTOP_TASK_REGRESSION.md) — dated automated regression, category storage/state/UI checks, History read/state/integration checks, local builds, and retained artifact identity.
- [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md) — dated actual-interface observations, category and History fixtures, partial acceptance, and blocked/untested production and system checks.
- [Task categories handoff](TASK_CATEGORIES_HANDOFF.md) — category source/artifact identity, automated and interface evidence, completed documentation, and the remaining TASK-011 acceptance gate.

## Historical evidence

- [Notes MVP regression](NOTES_MVP_REGRESSION.md) — original 2026-09-27 compact-panel build/test evidence.
- [Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) — original compact-panel/fixture observations and system-menu-bar limitations. These results do not establish desktop acceptance.

## Local plans

The [Today / Later implementation plan](../plan/later-tasks/later-tasks.md) proposes an undated Later list with text/category only and explicit Move to Today; the feature is not yet implemented.

The [History, Unfinished, and monthly calendar plan](../plan/task-history/task-history.md) records the implemented History feature's task cards, evidence, and handoff.

The [task-categories plan](../plan/task-categories/task-categories.md) defines the category implementation and acceptance sequence. The [desktop task-management plan](../plan/desktop-task-management/desktop-task-management.md) defines the preceding desktop increment. The earlier [Notes MVP design](../plan/mvp/NOTES_MVP_PLAN.md) and [task cards](../plan/mvp/NOTES_MVP_TASKS.md) describe the superseded compact panel. The [initial roadmap](../plan/init/master_plan.md) records the historical demo-shell phase.

`plan/` and `build/` are ignored by Git and may be absent from another checkout. Current requirements and the tracked desktop evidence records stand on their own; local links provide additional detail without changing that Git policy.
