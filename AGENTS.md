# MenuPocket

MenuPocket is a native macOS desktop and menu bar app built with SwiftUI and AppKit. One reusable task window manages Today's daily tasks and an undated Later list; a retained menu bar item shows saved progress from the same SQLite-backed state. The earlier demo model still supports preferences and Settings. The repository directory is named `MenuPeek`.

## Where to look

- [`README.md`](README.md): prerequisites, quick start, and basic usage.
- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md): desktop task behavior, scope, and acceptance criteria.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [`docs/WORKFLOW.md`](docs/WORKFLOW.md): build, verification, and local Release steps.
- [`docs/DESKTOP_TASK_REGRESSION.md`](docs/DESKTOP_TASK_REGRESSION.md): dated automated regression, storage preservation, and local artifact evidence.
- [`docs/DESKTOP_TASK_ACCEPTANCE.md`](docs/DESKTOP_TASK_ACCEPTANCE.md): actual-interface evidence, dependency assumptions, and remaining evidence gaps.
- [`docs/LATER_TASKS_REGRESSION.md`](docs/LATER_TASKS_REGRESSION.md) and [`docs/LATER_TASKS_ACCEPTANCE.md`](docs/LATER_TASKS_ACCEPTANCE.md): Today/Later automated evidence, isolated-fixture interface results, and remaining production/system gaps.
- [`docs/TASK_CATEGORIES_HANDOFF.md`](docs/TASK_CATEGORIES_HANDOFF.md): category implementation/verification handoff and remaining acceptance gate.
- [`docs/NOTES_MVP_REGRESSION.md`](docs/NOTES_MVP_REGRESSION.md) and [`docs/NOTES_MVP_ACCEPTANCE.md`](docs/NOTES_MVP_ACCEPTANCE.md): historical compact-panel evidence; preserve their original results.
- [`docs/index.md`](docs/index.md): documentation entry point, including local desktop/MVP plans and the historical roadmap. `plan/` is ignored by Git and may be absent from other checkouts.

## Project rules

- Preserve saved notes, preferences, and launch-at-login state when changing persistence or replacing demo behavior. Do not overwrite data with an unsupported newer schema.
- Keep the app local and sandboxed. Add external services, permissions, or dependencies only when a selected feature requires them.
- Use the shared `MenuPocket` Xcode scheme for builds and tests. Verify changes to menu bar, panel, or Settings behavior in the running macOS interface; a build or unit test alone does not establish that interaction works.
- Use English implementation plans as the sole source of truth for execution, verification, handoff, and future plan updates. Do not consult, reference, validate, or maintain initial-reading copies during subsequent work.
- After every build/test/UI verification session, including failed runs, stop and remove the temporary app bundles you created for testing before reporting completion. This includes Debug test hosts and renamed fixtures. Preserve the user's main app and saved data; follow [test artifact cleanup](docs/WORKFLOW.md#test-artifact-cleanup).

Update the relevant document when its guidance changes. Change this entry point only when project-wide rules, project identity, or the document map changes.
