# History

History replaces the Today content in the same window with a read-only month calendar. Each day shows the completed/total count for the tasks currently saved on that day, and a selected day's detail lists its tasks by category with All, Unfinished, and Completed filters. Unfinished from previous days lists earlier days that still have unfinished tasks. History never writes saved data.

## Sub-features

- `history-open` opens on yesterday from the calendar button; Back to Today returns and keeps the Today draft.
- `history-calendar` uses Previous month, Next month, and This month, with per-day labels such as `0 of 1 complete`, `No tasks`, and `Not yet`.
- `history-detail` shows the selected day's title, `N of M tasks complete`, View only, and grouped read-only rows.
- `history-filter` changes the rows shown (All, Unfinished, Completed), not the count.
- `history-unfinished` lists earlier unfinished days, opens a day with the Unfinished filter, and offers Back to Unfinished and Go to Today.
- `history-yesterday` opens yesterday with the Unfinished filter from the Today reminder.
- `history-read-only` leaves the database unchanged after browsing.

## How to get to it (user POV)

- Click the calendar button beside Today's date (`View task history`).
- Click the `N unfinished tasks from yesterday` reminder on Today.
- Choose `Unfinished from previous days` inside History.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`. Yesterday has 1 of 2 complete; three days ago has 0 of 1.
- Take `$F snapshot <run> before-history` now; it is the read-only baseline.

- **Open History.** Run `$F ax <run> press id=taskHistoryEntry` and `$F ax <run> wait id=historyCalendar`. `value id=taskBrowserHeading` reads `History`, `id=historyMonth` names the current month, and yesterday's `id=historyCalendarDay-<yyyy-mm-dd>` is `[selected]`. `value id=historyDayProgress` reads `1 of 2 tasks complete`.
- **Pick a day.** Run `$F ax <run> press id=historyCalendarDay-<three days ago>`. `value id=historyDayTitle` names that date, and one row `label~=Not completed: Renew library books` (an `id^=historyTaskRow-` element) is listed.
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
