# MenuPocket documentation

MenuPocket manages daily tasks in one desktop window and shows saved progress in the menu bar. These tracked documents describe the current product and its verification evidence:

- [README](../README.md) — prerequisites, quick start, tests, and a short usage guide.
- [Requirements](REQUIREMENTS.md) — desktop task behavior, daily-only scope, and acceptance criteria.
- [Architecture](ARCHITECTURE.md) — app composition, data flow, persistence, and system boundaries.
- [Workflow](WORKFLOW.md) — build, verification, and local Release steps.
- [Desktop regression](DESKTOP_TASK_REGRESSION.md) — dated automated regression, category storage/state/UI checks, local builds, and retained artifact identity.
- [Later tasks regression](LATER_TASKS_REGRESSION.md) — integrated Today/Later tests, changed-data reopen, Debug/Release identity, preservation and cleanup; native acceptance remains pending.
- [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md) — dated actual-interface observations, category fixtures, partial acceptance, and blocked/untested production and system checks.
- [Task categories handoff](TASK_CATEGORIES_HANDOFF.md) — category source/artifact identity, automated and interface evidence, completed documentation, and the remaining TASK-011 acceptance gate.

## Historical evidence

- [Notes MVP regression](NOTES_MVP_REGRESSION.md) — original 2026-09-27 compact-panel build/test evidence.
- [Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) — original compact-panel/fixture observations and system-menu-bar limitations. These results do not establish desktop acceptance.

## Local plans

The [Today / Later implementation plan](../plan/later-tasks/later-tasks.md) tracks the implemented undated Later list with text/category only and explicit Move to Today. Integrated automated verification has passed; assembled-feature native acceptance remains pending.

The [task-categories plan](../plan/task-categories/task-categories.md) defines the category implementation and acceptance sequence. The [desktop task-management plan](../plan/desktop-task-management/desktop-task-management.md) defines the preceding desktop increment. The earlier [Notes MVP design](../plan/mvp/NOTES_MVP_PLAN.md) and [task cards](../plan/mvp/NOTES_MVP_TASKS.md) describe the superseded compact panel. The [initial roadmap](../plan/init/master_plan.md) records the historical demo-shell phase.

`plan/` and `build/` are ignored by Git and may be absent from another checkout. Current requirements and the tracked desktop evidence records stand on their own; local links provide additional detail without changing that Git policy.
