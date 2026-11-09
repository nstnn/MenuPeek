# History

History replaces Today in the same window with a month calendar and grouped day details. Browsing is read-only. Explicit Continue today creates new attempts for selected unfinished past tasks while marking originals; old completed/total remains unchanged. Continued originals appear under All with their destination date and are excluded from Unfinished filters, the index and yesterday reminders.

## Sub-features

- `history-open` opens on yesterday from the History control; Back to Today returns and keeps the Today draft.
- `history-calendar` uses Previous month, Next month, and This month, with per-day labels such as `0 of 1 complete`, `No tasks`, and `Not yet`.
- `history-detail` shows the selected day's title, `N of M tasks complete`, and grouped historical rows.
- `history-continue` selects one or more unfinished past tasks and explicitly continues them in Today; completed, continued, Today and future rows cannot be selected.
- `history-filter` changes the rows shown (All, Unfinished, Completed), not the count.
- `history-unfinished` lists earlier unfinished days, opens a day with the Unfinished filter, and offers Back to Unfinished and Go to Today.
- `history-yesterday` opens yesterday with the Unfinished filter from the Today reminder.
- `history-read-only` leaves the database unchanged after browsing.

## How to get to it (user POV)

- Click the History control in Today's Daybook rail (`View task history`).
- Click the `N unfinished tasks from yesterday` reminder on Today.
- Choose `Unfinished from previous days` inside History.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`. Yesterday has 1 of 2 complete; three days ago has 0 of 1.
- Take `$F snapshot <run> before-history` now; it is the read-only baseline.

- **Open History.** Run `$F ax <run> press id=taskHistoryEntry` and `$F ax <run> wait id=historyCalendar`. `value id=taskBrowserHeading` reads `History`, `id=historyMonth` names the current month, and yesterday's `id=historyCalendarDay-<yyyy-mm-dd>` is `[selected]`. `value id=historyDayProgress` reads `1 of 2 tasks complete`.
- **Pick a day.** Run `$F ax <run> press id=historyCalendarDay-<three days ago>`. `value id=historyDayTitle` names that date, and one row `label~=Unfinished: Renew library books` (an `id^=historyTaskRow-` element) is listed.
- **Filter.** Select yesterday again, then run `$F ax <run> press "role=AXRadioButton,label=Completed"`. Only `Completed: Send weekly report` remains, and `historyDayProgress` still reads `1 of 2 tasks complete`. Press `label=All` to restore.
- **Months.** Run `$F ax <run> press id=historyPreviousMonth`; `historyMonth` changes to the previous month. `press id=historyThisMonth` returns.
- **Unfinished.** Run `$F ax <run> press id=unfinishedHistoryEntry` and `$F ax <run> wait id=unfinishedDayList`. The rows `id=unfinishedDay-<yesterday>` and `id=unfinishedDay-<three days ago>` appear, newest first. Press one: its detail opens with the Unfinished filter, and `id=taskBrowserBack` returns to the list. `id=taskBrowserToday` (Go to Today) returns to Today.
- **Yesterday reminder.** From Today, run `$F ax <run> press id=yesterdayHistoryEntry`. History opens on yesterday with the Unfinished segment selected.
- **Back to Today keeps the draft.** Before opening History, start a draft (`press id=addTask`, `type "Keep me"`). After `press id=taskBrowserBack`, `value id=newTaskDraft` still shows `Keep me`.
- **Read-only proof.** Run `$F snapshot <run> after-history`. Its `db.txt` is identical to `before-history`, apart from intentional Today changes. Capture the calendar with `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/history.png`.

## Gotchas

- Day identifiers use the fixture's local date. Use `--now … --tz …` at launch when a recipe needs fixed dates, or read today's key from the launch log (`today=YYYY-MM-DD`) in `runs/<run>/fixture.log`.
- Future days are `AXUnknown` elements labeled `Not yet` and cannot be pressed.
- History, Unfinished, and the yesterday reminder are disabled while editing, confirming a deletion, or managing categories.
- The Unfinished list pages 31 days at a time. Testing `id=unfinishedLoadMore` needs a seed with more than 31 earlier unfinished days, which the `basic` seed does not have. Add a named seed in `FixtureMain.swift` rather than writing rows by hand, and until then report Load more as Not tested.
- `fixture.sh next-day` moves Today forward one day, so yesterday becomes the seeded Today. This is a simulated day change, not a real midnight.

## Continue today recipe

Use `basic` with `--now 2026-10-22T16:00:00Z --tz America/Toronto`. Take a snapshot before changing anything. The seed has four Today tasks (1/4) and yesterday has Call the dentist unfinished plus Send weekly report completed (1/2).

1. Open `id=yesterdayHistoryEntry`. `id=continueHistoryTasks` is disabled until selection. Inspect `tree` for the checkbox `id=continueSelection-<source UUID>`, labeled Select Call the dentist to continue today. Press it, then the Continue today button. Verify the success message `id=historyContinuationMessage`, History still at 1/2, no unfinished row, and no second continuation action for this source.
2. Choose All. The source says Continued on Oct 22, 2026. Save a snapshot: source rowid/UUID/text/category/day/timestamps/completion/order remain; only continued_on changes. A fresh target UUID is appended to Today with matching text/category, no completion and the action-time creation instant. Menu bar is now 1/5.
3. Go back to Today: the dentist task appears, yesterday reminder is absent. Create a Today draft before another History visit and verify it survives. On Oct 19, continue Renew library books through keyboard focus/Space and the focused Continue today action; menu bar becomes 1/6. Inspect Unfinished: the original dates no longer qualify.
4. Select Today in History: there are no continuation selection checkboxes. Completed rows and marked originals also have none. Changing the selected day or filter clears an uncommitted selection; returning to the earlier source cannot continue it again.
5. Stop, snapshot stored state, relaunch the same artifact without reseeding and snapshot again. Compare UUIDs/markers/order and the displayed historical result/Today count. Complete the new dentist attempt through Today, then verify yesterday stays 1/2.
6. For batch selection after a simulated next-day, Today becomes yesterday: select two unfinished rows, press Continue today once, and confirm exactly two targets and two markers, with unchanged historical progress. Simulated rollover and hosted failure tests do not prove genuine midnight/time-zone or real disk failure behavior.

Stable handles: `continueHistoryTasks`, `continueSelection-<source UUID>`, `historyContinuationMessage`. Selection checkboxes choose work; they do not complete historical tasks. Save before/after snapshots and actions, then clean the run and hosted test bundles using the skill cleanup rules.
