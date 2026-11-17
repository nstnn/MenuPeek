# Compact History — 2026-11-13

The approved Compact calendar (Lịch gọn) design is implemented. History uses the persistent sidebar to return to Today/Later, a smaller date navigator, and a dominant plain task detail pane. No schema, repository transaction, dependency or production-data change is included. No installation, commit, push or PR was requested.

## Implementation

- Removed Back to Today and redundant Go to Today; kept contextual Back to History/Unfinished. The index entry is Review unfinished….
- Month cells show a dot only when saved tasks exist, exact counts/status in accessibility/help, underlined Today and tinted/outlined selection. Month error/Retry and unavailable markers remain distinct from empty data.
- Calendar width is240–260 pt beside detail at content widths >=700 pt; narrower columns stack a calendar capped at280 pt above detail. `AnyLayout` preserves selection state. Focused selection controls are revealed after a layout change.
- Populated detail has one textual year/progress summary, existing filters and category disclosure, plain row dividers and selectable task text. Continued dates appear under text. Loaded empty days omit progress/filters/continuation controls.
- Select tasks to continue… enters explicit selection mode. Checkbox selection never changes old completion. Cancel/Escape clears selection and restores selector focus, including when keyboard focus has moved to calendar/header/sidebar. Day/filter/Today changes also clear selection. Failed Continue keeps selection; only successful saves exit mode.
- Keyboard cancellation is scoped to History/Unfinished-day and excludes Categories/Settings. Today drafts and existing route guards remain owned by their current state/controller.

Files: `TaskBrowserView.swift`, `TaskHistoryView.swift`, `TaskHistoryCalendarView.swift`, `HistoryDayDetailView.swift` under `MenuPocket/Notes/`, plus requirements, architecture, workflow and the History verification recipe. Pre-existing changes to `TaskWindowView.swift` and `features/daybook.md` were preserved and included as build inputs, not authored by this task.

## Exact source and native artifacts

Branch `fix/shared-pane-canvas`, HEAD `a6155b77c16627b58f2dc3f3790aa1d440f97d79`, uncommitted working tree. Xcode27.0 (27A266a), Swift6.4, macOS GUI. Source identity includes the pre-existing app edits above.

Final fixture `20261113-120303`:

- All app Swift sources SHA256: `644473361546b75ec496bf869cc94e76208e2d4aa3c6611f88e271a6399346e2`.
- Executable SHA256: `bdbb179a8860dc089f6d66d5a15c5b921b37f09895fd42b025c7a2508e5576a2`.
- Bundle ID `local.menupocket.verify.r20261113-120303`; isolated SQLite/defaults; fake login-item/hotkey services.
- Basic seed, injected clock `2026-11-13T16:00:00Z`, America/Toronto. Agent-operated native CUA input; fixture snapshots record AX, screenshot, SQLite rows/defaults.
- Raw evidence: `build/verify-menupocket/evidence/20261113-120303/`. Its temporary app is removed after verification; evidence remains ignored by Git.

## Results

Recorded final focused-test invocation:

```sh
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/history-compact/DerivedData \
  -resultBundlePath build/history-compact/history-escape-final.xcresult \
  -only-testing:MenuPocketTests/TaskHistoryStateTests \
  -only-testing:MenuPocketTests/TaskHistoryCalendarTests \
  -only-testing:MenuPocketTests/TaskHistoryIntegrationTests \
  -only-testing:MenuPocketTests/UnfinishedTasksStateTests test
```

| Check | Result and evidence |
| --- | --- |
| Final build and focused tests | **Pass.** Fixture compiles. Shared MenuPocket scheme Debug:30 affected tests, zero failures, `build/history-compact/history-escape-final.log` and `.xcresult`. Calendar, History/Unfinished state and real-SQLite integration including rollback/retry. |
| Compact populated History | **Pass.** Final snapshot `01-final-populated`: no Back to Today, dot calendar, exact AX counts, plain groups and combined summary. |
| Escape from sibling focus | **Pass.** Final snapshot02: checked dentist task,1 selected, calendarNov21 focused. Snapshot03: Escape removes selection controls and restores selector focus. This fixed a reproduced failure saved in earlier115324 snapshot10. |
| Focus and selection across layout change | **Pass.** Final snapshot04: native Command-plus changes to stacked layout, same checked/focused UUID and1 selected remain, and automatic scrolling makes checkbox/footer visible. Command-0 restores wide layout. No manual scroll manufactured this result. |
| Draft and browsing preservation | **Pass.** Final snapshot05: sidebar Today restores exact draft `Keep this Today draft`. Final `browse-before.sql`/`browse-after.sql` are byte-identical; selection/cancellation/zoom did not write task data. |
| Empty day/filter/Light | **Pass on115324**, before the final Escape-only scope correction. Snapshots03/04/07 distinguish loaded empty and filtered states, keep whole-day counts, omit inappropriate continuation controls, and show native Light. Initial populated snapshots show Dark. Rendering/data owners are unchanged by the final cancellation bridge. |
| Continuation and changed-data relaunch | **Pass on115324**, before the final Escape-only scope correction. Snapshots05/06 show one source marker and one new Today attempt, old progress1/2 unchanged, Today1/4→1/5. Snapshots08/09 preserve identical row IDs/order/markers and preferences after quit/relaunch without reseeding; native Today contains the new attempt. No persistence code changed afterward. |
| Longer text and nested routing | **Supporting earlier native evidence111236.** Long task wraps; sidebar/draft retention and contextual Unfinished back paths were observed. These are not presented as new final-source acceptance of unrelated features. |
| Cleanup | **Pass.** Every fixture created for this task was stopped/trashed/unregistered, including failed builds. Final `cleanup.txt` confirms no process/original bundle/LaunchServices/defaults remains. Hosted and independent-baseline test app bundles were also trashed/unregistered. Installed `/Applications/MenuPocket.app` remains intact. |

Full-suite limitation: `build/history-compact/tests-final.log` executed455 test cases;454 passed and one Settings Command-W lifecycle test failed three assertions (`AppConfigurationTests.swift:1483,1484,1487`). It also failed alone. The independent reviewer reproduced those exact assertions on HEAD plus only the pre-existing `TaskWindowView.swift` edits, with all four History files restored to HEAD (`review-baseline-settings-native.log`/`.xcresult`). This failure is not attributable to this History patch. Its cause was not diagnosed; **the full suite is not claimed green**. The earlier455/0 run is historical after subsequent UI changes.

Native failed-write recovery, pane error/Retry, VoiceOver, pointer resize/minimum-size enforcement, real midnight/wake/time-zone events and production/system integrations remain **Not tested**. Hosted rollback/retry and direct failure-branch inspection are narrower evidence. The current fixture has no sanctioned continuation-write fault seed, and its skill forbids manufacturing live SQLite/defaults state outside named seed preconditions.

Independent reviewer `/root/review_history` did not author the changes, inspected actual source/callers, raw tests and screenshots/AX, reproduced the baseline test failure and checked final evidence. Detailed report: `build/history-compact-review.md` (local evidence; scope and residual limits apply). No remote CI or release approval is implied.

## Calendar position correction — 2026-11-17

`TaskHistoryView` now gives the calendar pane its natural vertical size with
`fixedSize(horizontal: false, vertical: true)`. The top-aligned layout no longer
redistributes calendar spacing when the sibling detail grows or shrinks. Width
constraints, responsive stacking, filtering and storage behavior remain unchanged.
The History verification recipe includes a long/short/empty-detail geometry check.

Source: `97e7f9c615a70568111116835c2acabffb83df99` plus only the calendar-pane
source change. Xcode 27.0 (27A266a), Swift 6.4; shared `MenuPocket` Debug scheme.
**Pass:** 23 focused tests in `TaskHistoryStateTests`, `TaskHistoryCalendarTests`
and `TaskHistoryIntegrationTests`, zero failures. Log:
`build/history-calendar-layout-tests.log`; result bundle:
`build/DerivedData/Logs/Test/Test-MenuPocket-2026.11.17_16-25-45--0500.xcresult`.
The full suite was not run for this layout-only correction.

Native observations below are agent-operated on isolated fixtures with the
`category-reordering` seed, fixed `2026-11-17T17:00:00Z` clock, America/Toronto,
and fake login/hotkey services. A simulated next-day made the 28-task seeded day
historical. Raw identity, actions, screenshots, AX, database/defaults snapshots
and cleanup reports are in `build/verify-menupocket/evidence/<run>/`.

| Check | Result |
| --- | --- |
| Baseline reproduction, run `20261117-162403` | **Pass, reproduced defect.** All → Completed moved the month label from y=196 to 188 and the calendar from y=230 to 223 pt. Snapshots 01–02. Startup first timed out; doctor and a stack sample recorded a directory-open wait during SQLite commit. The same instance subsequently became ready; no duplicate launch. |
| Fixed wide layout, run `20261117-162542`, PID 49256 | **Pass.** All, Completed, Unfinished and long-group collapse/expand keep identical month `(499,188,96,15)`, calendar `(499,223,240,239)`, selected-day `(568,331,31,41)` and This month `(499,500,101,26)` frames in screen points. Snapshots 01–04; database and decoded defaults are identical. |
| Empty Unfinished → long All | **Pass.** Continued all 26 unfinished rows through visible selection controls, then returned through Today/History. Empty Unfinished and All with continued originals keep exactly those same four frames; historical progress stays 2/28. Snapshots 05–06 have identical database/defaults. The continuation itself intentionally created 26 Today attempts and source markers in fixture data. |
| Stacked layout and keyboard | **Pass.** Native ⌘+ gives stacked layout at 1.1 zoom. All/empty Unfinished retain identical month `(523,238,106,16)`, calendar `(523,276,308,262)`, selected-day `(612,395,40,45)` and This month `(523,581,111,28)` frames. Snapshots 07–08. Right Arrow moves focus Nov 17 → Nov 18 while selection/progress remain Nov 17, 2/28 (snapshot 09); ⌘0 restores actual size. |

Final fixture app-source SHA256:
`3004e457afb0de5906b9d6396b229e0f6373d4c850f2cfcd71fc11ccc41d52e9`;
executable SHA256:
`003b0b6a99a17bfa9c0a08e982ddabab0cf23aa5c7a718413ddb925c208482e2`.
Bundle ID `local.menupocket.verify.r20261117-162542`, version `0.0.0-verify`/1;
bundle and SQLite paths are recorded in `identity.json`. No production data,
installation or system integration was exercised. Native checks used Dark;
Light, physical resize, VoiceOver and genuine rollover are **Not tested** here.

All three temporary fixture attempts (including sandbox compile failure
`20261117-162334`) and the Debug XCTest host are cleaned after this session;
individual cleanup reports retain the results. The user's running
`/Applications/MenuPocket.app` (PID 5987) is preserved.
