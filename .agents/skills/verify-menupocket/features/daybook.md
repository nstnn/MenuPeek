# Daybook task window

Today and Later use the approved Daybook layout: a warm Light/Dark paper canvas, serif date rail and heading, native destination control, flat task groups and subtle row rules. Existing add/edit/cancel, actions, movement, History and Settings behavior stays intact. Only Today has a date and progress ring.

## Sub-features

- `daybook-layout`: normal 920 × 640 pt and minimum 600 × 400 pt; compact rail below 740 pt width or 480 pt height.
- `daybook-navigation`: Today/Later in the rail; History and Categories below. History has native title-bar destinations and Settings while it replaces the rail.
- `daybook-states`: empty, unavailable/Retry, long text, long category, completed, active editor and deletion confirmation.
- `daybook-drafts`: native fields, category picker, Save/Cancel, Return/Escape, retained drafts and Undo across window reopen.

## How to get to it (user POV)

- Open the task window from the menu bar count or app launch.
- Use the rail for Today, Later, History, Categories and Settings.
- Choose Add task or Command-N; use the row ellipsis for Edit, Move and Delete.

## Driving it with fixture.sh + mpax

Preconditions:

- Build a fresh isolated fixture and launch with `--seed basic`; doctor must pass. Start with `$F snapshot <run> before-daybook`.
- **Today appearance.** `$F ax <run> value id=daybookDate` exposes the saved civil date. `$F ax <run> value id=todayProgress` exposes `1 of 4 complete` (the visible text is `1/4 complete`); screenshot the date rail and flat groups with `$F snapshot <run> today-daybook`.
- **Later.** `$F ax <run> press id=laterTab`, then `$F ax <run> wait id=laterTaskList`. `$F ax <run> gone id=daybookDate` and `gone id=todayProgress` succeed. Remaining count is shown; no date or ring is visible. Return with `press id=todayTab`.
- **Add/edit/delete/move.** Follow [Today](today-tasks.md) and [Later](later-list.md) on this build. Snapshot before/after; compare SQLite rows and saved order as well as counts. Test Cancel before any confirmed deletion.
- **Child routes.** `press id=taskHistoryEntry` opens History; its title-bar Today/Later controls remain available. Return with `press id=todayTab`. `press id=manageCategories` opens the existing sheet. Close with its Done action. `press "label=Open Settings"` opens the existing Settings window.
- **Appearance.** Change Theme through Settings on the isolated fixture only, observing Light and Dark. Restore the fixture setting afterward. Capture both with `snapshot`.
- **Window sizes.** Use actual window-corner dragging through an available native UI adapter to inspect 600 × 400 pt content and 920 × 640 pt. The AX driver has no resize command. Record measured window size; do not equate screenshot pixels with AppKit points. Verify draft/category/Save/Cancel and deletion buttons remain reachable, with usable task-list scrolling. Snapshot each size.
- **Persistence.** After intentional fictional task changes, `stop`, `snapshot stopped`, `launch` the same run without reseeding, `snapshot relaunched`. Compare `db.txt`, preferences, saved count and visible rows.
- **Recovery.** Use `fail-open on`, stop/launch, observe Unavailable and disabled Add. Use `fail-open off`, press `id=retryTodayTasks`, and snapshot the recovered list. This is a simulated read failure.

## Gotchas

- The date rail uses the saved civil day key, not a second time-zone conversion. Later must never expose that date or Today progress.
- Native checkboxes, text fields and menus remain native. The serif heading and color palette do not replace keyboard/focus or persistence contracts.
- Add task is replaced by the composer while it is open. Finish or cancel it before locating `id=addTask` again.
- While editing, confirming deletion, or managing categories, destination switches and conflicting actions remain guarded.
- Browser concept screenshots are design references, not evidence for this native build. Pointer drag behavior, VoiceOver and real system integrations require their own observations.
