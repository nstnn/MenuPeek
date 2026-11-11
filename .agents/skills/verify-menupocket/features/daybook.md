# Daybook task window

Today and Later use the approved Daybook layout: a warm Light/Dark paper canvas, serif date rail and heading, native destination control, flat task groups and subtle row rules. Existing add/edit/cancel, actions, movement, History and Settings behavior stays intact. The shared rail keeps today’s date, explicitly labeled Today progress, and navigation in the same positions on Today, Later, History, Categories, and Settings. Later’s main content remains undated.

## Sub-features

- `daybook-layout`: initial 1000 × 700 pt and minimum 800 × 560 pt content; both retain the full 218 pt rail. The compact layout remains a defensive fallback below 740 pt width or 480 pt height.
- `daybook-navigation`: Today/Later in the rail; History and Categories below. History, Categories and Settings replace only the right detail column; the rail stays visible and interactive. Idle Categories allows navigation away; rename and removal confirmation block it. Settings entry points, including Command-comma, reuse the same task window.
- `daybook-states`: empty, unavailable/Retry, long text, long category, completed, active editor and deletion confirmation.
- `daybook-drafts`: native fields, category picker, Save/Cancel, Return/Escape, retained drafts and Undo across window reopen.
- `daybook-buttons`: buttons without their own style use `DaybookButtonStyle`. Every button is a capsule. Quiet actions (Cancel, Retry, This month, Go to Today, Load more, Done, Rename, Settings actions) have a hairline outline and secondary text; on hover the text turns primary and the outline darkens. One prominent action per view sits on a soft terracotta tint with accent text and fills solid terracotta on hover: composer Save, category Create and rename Save, and History Continue today. Destructive roles swap the accent for red: quiet Remove… is outlined red text, and the confirming Delete and Remove Category sit on a red tint that fills red on hover. Disabled buttons fade to 40%.

## How to get to it (user POV)

- Open the task window from the menu bar count or app launch.
- Use the rail for Today, Later, History, Categories and Settings.
- Choose Add task or Command-N; use the row ellipsis for Edit, Move and Delete.

## Driving it with fixture.sh + mpax

Preconditions:

- Build a fresh isolated fixture and launch with `--seed basic`; doctor must pass. Start with `$F snapshot <run> before-daybook`.
- **Today appearance.** `$F ax <run> value id=daybookDate` exposes the saved civil date. `$F ax <run> value id=todayProgress` exposes `1 of 4 complete` (the visible text is `Today: 1/4 complete`); screenshot the date rail and flat groups with `$F snapshot <run> today-daybook`.
- **Later.** `$F ax <run> press id=laterTab`, then `$F ax <run> wait id=laterTaskList`. `$F ax <run> value id=daybookDate` and `value id=todayProgress` retain the same values and positions as Today. History, Categories and Settings remain visible. The main pane shows Later and its remaining count. Return with `press id=todayTab`.
- **Add/edit/delete/move.** Follow [Today](today-tasks.md) and [Later](later-list.md) on this build. Snapshot before/after; compare SQLite rows and saved order as well as counts. Test Cancel before any confirmed deletion.
- **Child routes.** `press id=taskHistoryEntry` opens History; its title-bar Today/Later controls remain available. Return with `press id=todayTab`. Also enter History from Later and verify Back to Today returns to Today without changing either list. `press id=manageCategories` opens the existing sheet. Close with its Done action. `press "label=Open Settings"` opens the existing Settings window.
- **Buttons.** With the composer open, `value id=saveTask` reports `[disabled]` until text is typed, and `press id=saveTask` still saves. `press id=cancelNewTask` still cancels. Open a row's Delete… and confirm that `press id=cancelTaskDeletion` keeps the task and `press id=confirmTaskDeletion` removes it from `db.txt`. In History, `press id=historyThisMonth` and `id=continueHistoryTasks` still act. With Tab navigation, Save, Cancel, Delete and Retry still take focus and respond to Space. Screenshot the composer, the deletion confirmation, the category manager and History in Light and Dark; hover appearance needs a pointer and is Not tested through AX.
- **Appearance.** Change Theme through Settings on the isolated fixture only, observing Light and Dark. Restore the fixture setting afterward. Capture both with `snapshot`.
- **Window sizes.** Use actual window-corner dragging through an available native UI adapter to inspect 800 × 560 pt content and 1000 × 700 pt. Confirm an attempted drag below the minimum stops at 800 × 560 pt. The AX driver has no resize command. Record measured window size; do not equate screenshot pixels with AppKit points. Verify draft/category/Save/Cancel and deletion buttons remain reachable, with usable task-list scrolling. Snapshot each size.
- **Persistence.** After intentional fictional task changes, `stop`, `snapshot stopped`, `launch` the same run without reseeding, `snapshot relaunched`. Compare `db.txt`, preferences, saved count and visible rows.
- **Recovery.** Use `fail-open on`, stop/launch, observe Unavailable and disabled Add. Use `fail-open off`, press `id=retryTodayTasks`, and snapshot the recovered list. This is a simulated read failure.

## Gotchas

- The date rail uses the saved civil day key, not a second time-zone conversion. The shared rail always describes Today; Later tasks remain undated and never contribute to Today progress.
- Native checkboxes, text fields and menus remain native. The serif heading and color palette do not replace keyboard/focus or persistence contracts.
- Add task is replaced by the composer while it is open. Finish or cancel it before locating `id=addTask` again.
- While editing, confirming deletion, or managing categories, destination switches and conflicting actions remain guarded.
- Browser concept screenshots are design references, not evidence for this native build. Pointer drag behavior, VoiceOver and real system integrations require their own observations.
