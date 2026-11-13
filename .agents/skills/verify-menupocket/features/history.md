# History

History replaces Today in the same window with a month calendar and grouped day details. Browsing is read-only. Explicit Continue today creates new attempts for selected unfinished past tasks while marking originals; old completed/total remains unchanged. Continued originals appear under All with their destination date and are excluded from Unfinished filters, the index and yesterday reminders.

## Sub-features

- `history-open` opens on yesterday the first time from the History control (later visits in the same run keep the last day and filter); the sidebar Today/Later controls return and keep the drafts. History has no Back to Today button.
- `history-calendar` uses Previous month, Next month, and This month, with per-day labels ending in a status such as `0 of 1 complete`, `No tasks`, or `Not yet` (for example `Monday, October 19, 2026, 0 of 1 complete`; match with `label~=`). This month selects Today with the All filter.
- `history-detail` shows the selected day's title, one year/completed-total line and grouped historical rows without card surfaces. Loaded empty days show No tasks saved and omit progress, filters and continuation controls. A filter with no matches keeps the filters and whole-day counts.
- `history-continue` selects one or more unfinished past tasks and explicitly continues them in Today; completed, continued, Today and future rows cannot be selected.
- `history-filter` changes the rows shown (All, Unfinished, Completed), not the count.
- `history-unfinished` lists earlier unfinished days and opens a day with the Unfinished filter. Contextual Back to History/Unfinished remains; Today/Later navigation uses the sidebar.
- `history-yesterday` opens yesterday with the Unfinished filter from the Today reminder.
- `history-read-only` leaves the database unchanged after browsing.

## How to get to it (user POV)

- Click the History control in Today's Daybook rail (`View task history`).
- Click the yesterday reminder on Today (`1 unfinished task from yesterday` with the `basic` seed; plural for more).
- Choose `Review unfinished…` inside History.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`. Yesterday has 1 of 2 complete; three days ago has 0 of 1.
- Take `$F snapshot <run> before-history` now; it is the read-only baseline.

- **Open History.** Run `$F ax <run> press id=taskHistoryEntry` and `$F ax <run> wait id=historyCalendar`. `value id=taskBrowserHeading` reads `History`, `id=historyMonth` names the current month, and yesterday's `id=historyCalendarDay-<yyyy-mm-dd>` is `[selected]`. `value id=historyDayProgress` reads `1 of 2 tasks complete`. Do this first: History keeps its last day and filter for the rest of the run, so after the yesterday reminder or an Unfinished day it reopens with Unfinished selected.
- **Pick a day.** Run `$F ax <run> press id=historyCalendarDay-<three days ago>`. `value id=historyDayTitle` names that date, and one row `label~=Unfinished: Renew library books` (an `id^=historyTaskRow-` element) is listed.
- **Filter.** Select yesterday again, then run `$F ax <run> press "role=AXRadioButton,label=Completed"`. Only `Completed: Send weekly report` remains, and `historyDayProgress` still reads `1 of 2 tasks complete`. Press `label=All` to restore.
- **Months.** Run `$F ax <run> press id=historyPreviousMonth`; `historyMonth` changes to the previous month. `press id=historyThisMonth` returns and selects Today (`label~=Today\,`).
- **Unfinished.** Run `$F ax <run> press id=unfinishedHistoryEntry` and `$F ax <run> wait id=unfinishedDayList`. The rows `id=unfinishedDay-<yesterday>` and `id=unfinishedDay-<three days ago>` appear, newest first. `id=taskBrowserBack` reads `Back to History` here. Press a day: its detail opens with the Unfinished filter, and `id=taskBrowserBack` (`Back to Unfinished`) returns to the list. `id=todayTab` returns to Today.
- **Yesterday reminder.** From Today, run `$F ax <run> press id=yesterdayHistoryEntry`. History opens on yesterday with the Unfinished segment selected.
- **Sidebar Today keeps the draft.** Before opening History, start a draft (`press id=addTask`, `type "Keep me"`). After `press id=todayTab`, `value id=newTaskDraft` still shows `Keep me`. Verify `taskBrowserBack` is absent on the calendar screen.
- **Compact calendar and empty day.** Dates with tasks have dots; other loaded dates have no count/dash. Today is underlined; selection has a tint/outline. Exact counts remain in AX/help. Select an empty past date: `historyDetailMessage` says No tasks saved, with no `historyDayProgress`, `historyFilter`, or `selectHistoryTasks`. Month failure remains an error with Retry, not an apparently empty month. Check the 240–260 pt calendar beside detail at wide content widths and the capped calendar stacked above detail in narrow columns; inspect Light/Dark, zoom, long task text and focused-control reveal.
- **Read-only proof.** Run `$F snapshot <run> after-history`. Its `db.txt` is identical to `before-history`, apart from intentional Today changes. Capture the calendar with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/history.png`.

- **Shared sidebar.** After opening History, `value id=daybookDate`, `value id=todayProgress`, `value id=manageCategories`, and `value "label=Open Settings"` remain reachable. Open Categories then Settings directly; `windows` lists one task window and no sheet. Use `press id=taskHistoryEntry` to return to History, or `press id=laterTab` to return to Later.

## Gotchas

- Day identifiers use the fixture's local date. Use `--now … --tz …` at launch when a recipe needs fixed dates, or read today's key from the launch log (`today=YYYY-MM-DD`) in `runs/<run>/fixture.log`.
- Future days are `AXUnknown` elements whose label ends in `Not yet` (for example `Thursday, October 29, 2026, Not yet`), so query them with `label~=Not yet`. They cannot be pressed unless the day already has saved rows.
- History, Unfinished, and the yesterday reminder are disabled while editing, confirming a deletion, renaming a category, or confirming a category removal. They stay available from the idle Categories pane.
- The Unfinished list pages 31 days at a time. Testing `id=unfinishedLoadMore` needs a seed with more than 31 earlier unfinished days, which the `basic` seed does not have. Add a named seed in `FixtureMain.swift` rather than writing rows by hand, and until then report Load more as Not tested.
- `fixture.sh next-day` moves Today forward one day, so yesterday becomes the seeded Today. This is a simulated day change, not a real midnight.

## Continue today recipe

Use `basic` with `--now 2026-10-22T16:00:00Z --tz America/Toronto`. Take a snapshot before changing anything. The seed has four Today tasks (1/4) and yesterday has Call the dentist unfinished plus Send weekly report completed (1/2).

1. Open `id=yesterdayHistoryEntry`. No selection checkboxes appear initially. Press `id=selectHistoryTasks`; `id=continueHistoryTasks` is disabled until selection. Inspect `tree` for `id=continueSelection-<source UUID>`, labeled Select Call the dentist to continue today. Check the first eligible checkbox receives focus (or Cancel if every group is collapsed). Cancel or Escape must exit selection without writes; reopening starts at 0 selected. Select the checkbox, then Continue today. Verify the success message `id=historyContinuationMessage`, History still at 1/2, no unfinished row, and no second continuation action for this source.
2. Choose All. The source says Continued on Oct 22, 2026. Save a snapshot: source rowid/UUID/text/category/day/timestamps/completion/order remain; only continued_on changes. A fresh target UUID is appended to Today with matching text/category, no completion and the action-time creation instant. Menu bar is now 1/5.
3. Go back to Today: the dentist task appears, yesterday reminder is absent. Create a Today draft before another History visit and verify it survives. On Oct 19, continue Renew library books through keyboard focus/Space and the focused Continue today action; menu bar becomes 1/6. Inspect Unfinished: the original dates no longer qualify.
4. Select Today in History: there are no continuation selection checkboxes. Completed rows and marked originals also have none. Changing the selected day or filter clears an uncommitted selection; returning to the earlier source cannot continue it again.
5. Stop, snapshot stored state, relaunch the same artifact without reseeding and snapshot again. Compare UUIDs/markers/order and the displayed historical result/Today count. Complete the new dentist attempt through Today, then verify yesterday stays 1/2.
6. For batch selection after a simulated next-day, Today becomes yesterday: select two unfinished rows, press Continue today once, and confirm exactly two targets and two markers, with unchanged historical progress. Simulated rollover and hosted failure tests do not prove genuine midnight/time-zone or real disk failure behavior.

Stable handles: `selectHistoryTasks`, `cancelHistorySelection`, `historySelectionCount`, `continueHistoryTasks`, `continueSelection-<source UUID>`, `historyContinuationMessage`. The selector is hidden on Completed and loaded empty days. Select mode does not write; a failed Continue retains selection for retry. After selecting a checkbox, Shift-Tab to a calendar/header/sidebar control without activating it, then Escape: selection mode must exit and focus must return to the selector, preserving the Today draft. Zoom across the wide/stacked threshold while a selected checkbox has focus: it remains checked and is scrolled into view. Checkboxes choose work; they do not complete historical tasks. Save before/after snapshots and actions, then clean the run and hosted test bundles using the skill cleanup rules.
