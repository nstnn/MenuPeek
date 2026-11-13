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
