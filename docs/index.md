# MenuPocket documentation

MenuPocket manages daily tasks in one desktop window and shows saved progress in the menu bar. These tracked documents describe the current product and its verification evidence:

- [README](../README.md) — prerequisites, quick start, tests, and a short usage guide.
- [Requirements](REQUIREMENTS.md) — desktop task behavior, daily-only scope, and acceptance criteria.
- [Architecture](ARCHITECTURE.md) — app composition, data flow, persistence, and system boundaries.
- [Workflow](WORKFLOW.md) — build, verification, and local Release steps.
- [Desktop regression](DESKTOP_TASK_REGRESSION.md) — 2026-09-29 automated regression, storage preservation, local builds, and retained artifact identity.
- [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md) — 2026-09-29 actual Release observations, partial acceptance, and blocked/untested system and fixture checks.

## Historical evidence

- [Notes MVP regression](NOTES_MVP_REGRESSION.md) — original 2026-09-27 compact-panel build/test evidence.
- [Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) — original compact-panel/fixture observations and system-menu-bar limitations. These results do not establish desktop acceptance.

## Local plans

The [desktop task-management plan](../plan/desktop-task-management/desktop-task-management.md) defines Tasks 1–10 for this increment. The earlier [Notes MVP design](../plan/mvp/NOTES_MVP_PLAN.md) and [task cards](../plan/mvp/NOTES_MVP_TASKS.md) describe the superseded compact panel. The [initial roadmap](../plan/init/master_plan.md) records the historical demo-shell phase.

`plan/` and `build/` are ignored by Git and may be absent from another checkout. Current requirements and the tracked desktop evidence records stand on their own; local links provide additional detail without changing that Git policy.
