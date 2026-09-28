# MenuPocket

MenuPocket is a native macOS menu bar app built with SwiftUI and AppKit. The current panel is a local daily notes checklist backed by SQLite; the earlier demo module shell still supports some app state and Settings. The repository directory is named `MenuPeek`.

## Where to look

- [`README.md`](README.md): prerequisites, quick start, and basic usage.
- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md): current and approved Notes MVP behavior, scope, and gaps.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): state, storage, and system boundaries.
- [`docs/WORKFLOW.md`](docs/WORKFLOW.md): build, verification, and local Release steps.
- [`docs/NOTES_MVP_REGRESSION.md`](docs/NOTES_MVP_REGRESSION.md): dated Debug build and hosted test evidence for the Notes MVP handoff.
- [`docs/NOTES_MVP_ACCEPTANCE.md`](docs/NOTES_MVP_ACCEPTANCE.md): dated interface observations and remaining Notes MVP acceptance checks.
- [`docs/index.md`](docs/index.md): documentation entry point, including links to the local Notes MVP plan and historical roadmap. `plan/` is ignored by Git and may be absent from other checkouts.

## Project rules

- Preserve saved notes, preferences, and launch-at-login state when changing persistence or replacing demo behavior. Do not overwrite data with an unsupported newer schema.
- Keep the app local and sandboxed. Add external services, permissions, or dependencies only when a selected feature requires them.
- Use the shared `MenuPocket` Xcode scheme for builds and tests. Verify changes to menu bar, panel, or Settings behavior in the running macOS interface; a build or unit test alone does not establish that interaction works.

Update the relevant document when its guidance changes. Change this entry point only when project-wide rules, project identity, or the document map changes.
