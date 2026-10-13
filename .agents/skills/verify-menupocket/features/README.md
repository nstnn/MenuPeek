# MenuPocket verification map

This directory is the maintained source for verifying what a MenuPocket user can see and do. Read this index before driving the app, then use the matching feature file as the recipe. Every command assumes the repository root and `F=.agents/skills/verify-menupocket/scripts/fixture.sh`.

## Baseline preconditions

- Ask before launching if someone may be using the Mac (see [SKILL.md](../SKILL.md#before-you-start)).
- Build a fresh fixture from the current working tree: `$F build`, which prints `RUN=<run>`.
- Launch it with the seed the recipe names, usually `$F launch <run> --seed basic`. Ready means the launch output ends in `Ready: PID …, status item: … title="1/4"` for `basic` or `title="0/0"` for `empty`.
- Run `$F doctor <run>` and require no `FAIL` lines.
- Drive only this run. Never drive `/Applications/MenuPocket.app` or another session's fixture.

## Driving conventions

- Start each recipe from a freshly launched run with the named seed, unless its preconditions say otherwise. Recipes that mutate data leave it changed, so build or launch a new run for a clean baseline.
- Prefer `id=` handles. Use `label=` for rows (`label=Actions for task: <text>`, `role=AXCheckBox,label=<text>`) and for menu items (`role=AXMenuItem,label=<title>`), whose identifiers are generic or change per run.
- Run every action through `$F ax <run> …` so it is logged to `actions.log`.
- Open a menu and press its item in consecutive calls (menus close if the fixture deactivates).
- Use `wait`/`gone` after view changes instead of fixed sleeps.

## Proof and skip reporting

- Take `$F snapshot <run> <label>` before and after the behavior under test. The proof is the change in `ax-tree.txt`/`window.png`, the status item value, and `db.txt`/`preferences.json`.
- Mutation proof includes the stored row or preference, not only the visible change.
- Persistence proof means `stop`, a snapshot while stopped, then relaunching the same run (no reseed) and comparing.
- Name the seed and any simulated boundary (`quickadd`, `next-day`, `fail-open`) in the report.
- Report an entry point that cannot be driven, such as a pointer drag or the real global hotkey, as Not tested, with the reason. Do not report it as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and a paragraph describing the user-visible behavior, then exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with fixture.sh + mpax` (starting with `Preconditions:`, then labeled bullets that pair a user action with exact commands and the observable result), and `Gotchas`. Keep implementation details out; name user paths, stable handles, required state, commands, and observable proof.

## Features

- [Today tasks](./today-tasks.md): add, complete, edit, and delete Today tasks, the composer, and keyboard routes.
- [Later list](./later-list.md): the undated Later tab, its remaining count, and Move to Today.
- [Categories](./categories.md): Manage categories (create, rename, remove), the category picker, group collapse, and row Move To.
- [History](./history.md): the read-only calendar, day detail and filters, Unfinished from previous days, and the yesterday entry.
- [Menu bar count and glance](./menu-bar.md): the status item's saved progress, click to Today, the right-click quick look, and Unavailable/Retry.
- [Settings and Quick Add](./settings-quick-add.md): the Settings window, Theme, Open at Login (faked), the Quick Add switch, and the capture panel.
