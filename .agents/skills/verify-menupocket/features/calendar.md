# Calendar

Calendar is a sidebar destination beside Today and Later. It replaces only the right content column with a pane that names the visible period, offers a Day/Week/Month switch (Week first), and moves with Previous, Today and Next. Calendar opens from Today or Later and leaves the selected list as it was. Day and Week show the saved blocks on a 24-hour time grid; the block editor and month cells are not built yet, so Month shows a one-line summary of the loaded period (`No blocks this month`, `2 blocks this month`). A failed read shows Calendar is unavailable with the period's message and Retry, never an empty calendar.

## Sub-features

- `calendar-entry`: the rail footer lists Calendar, a thin rule, History, Categories and Settings, in that order. Calendar uses the calendar symbol; History uses a clock symbol. The active entry is accent-colored, and History is not highlighted while Calendar is open.
- `calendar-route`: Calendar opens from Today and from Later, keeps the rail mounted, and leaves the Today/Later selection unchanged. Today, Later, History, Categories and Settings each leave it. Command-N and reopening the window from the menu bar return to the list.
- `calendar-guards`: like History, Calendar is disabled while a task edit, a task deletion confirmation, a category rename or a category removal confirmation is open. An idle category manager may be left for Calendar.
- `calendar-header`: the heading reads the period: Week `November 2026 · Week 47`, Day `November 2026 · Wednesday, November 18, 2026`, Month `November 2026`. Previous, Today and Next move by the current mode's unit; the view switch keeps the selected or current day in view.
- `calendar-grid`: Week shows seven day columns (Monday first) and Day one, under a fixed header row of weekday and date; today's date sits on an accent disc and its column is tinted. The grid scrolls vertically through 00:00–24:00 with an hour gutter, hour lines and dashed half-hour lines. On first appearance it scrolls to two hours before the current time when today is visible, else to 07:00; later period changes and reloads keep the scroll position.
- `calendar-blocks`: each saved block sits in its day's column from its start to its end (one point per minute at 100%). Overlapping blocks share the column side by side (halves, thirds); blocks that only touch keep full width. A block shows its title, then `10:00–11:00`, `10:00` or nothing as width allows; a title wraps only when its longest word fits, otherwise it truncates on one line. Blocks under 28 pt (the 15-minute block) show the title only. Hover shows the full title and time range.
- `calendar-now`: a red line with a dot marks the current minute across today's column only, refreshed each minute, and only while today's day is visible.
- `calendar-unavailable`: a failed read shows `Calendar is unavailable`, `Could not load this week. Try again.` (day/month in those modes) and Retry.

## How to get to it (user POV)

- Click Calendar at the bottom of the task window's rail, from Today or from Later.
- Leave by choosing Today or Later in the rail switch, or History, Categories or Settings.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed calendar --now 2026-11-18T15:00:00Z --tz America/Toronto` (Wednesday 18 November 2026, 10:00 local; the grid opens at 08:00). `--seed basic` works for the header and route checks and shows an empty grid. Take `$F snapshot <run> before-calendar`. `db.txt` does not list Calendar blocks yet; read them with `sqlite3 -readonly build/verify-menupocket/runs/<run>/data/fixture.sqlite "select title,day_key,start_minute,end_minute from schedule_blocks order by day_key,start_minute,created_at"`.

- **Sidebar order.** `$F ax <run> frame id=calendarEntry`, `frame id=taskHistoryEntry`, `frame id=manageCategories` and `frame "label=Open Settings"` have increasing `y`. `value id=calendarEntry` is labeled `Open Calendar`. The rule between Calendar and History is drawn only (not in the AX tree); confirm it in the screenshot.
- **Open from Today.** `$F ax <run> press id=calendarEntry`, then `wait id=schedulePane`. `value id=scheduleHeading` names the current week (`… · Week NN`), `value id=scheduleViewMode` reads `Week`, and `wait id=scheduleTimeGrid` succeeds. `value id=daybookDate` and `value id=todayProgress` still answer, and `value id=todayTab` is still selected. Snapshot `calendar-week`.
- **Navigate.** `press id=schedulePrevious`: the heading's week number drops by one. `press id=scheduleNext` twice: one week ahead. `press id=scheduleToday`: back to the first heading. Each heading change is the proof; `value id=schedulePrevious` is labeled `Previous week`.
- **Switch view.** `id=scheduleViewMode` is a radio group whose value is the current view. Choose a segment with `press "role=AXRadioButton,label=Day"` (or `Month`, `Week`); these are the only radio buttons with those labels in the window. Day: the heading includes the full date (`November 2026 · Wednesday, November 18, 2026`) and `id=schedulePrevious` is labeled `Previous day`. Day shows one `id^=scheduleDayHeader-` and only that day's blocks. Month: the heading is the month and year only, and `id=schedulePlaceholder` reads `N blocks this month`. Return to Week.
- **Open from Later.** `press id=laterTab`, `press id=calendarEntry`, `wait id=schedulePane`. `value id=laterTab` stays selected. `press id=laterTab` returns to Later's list (`wait id=laterTaskList`).
- **Leave through every entry.** From Calendar, `press id=taskHistoryEntry` shows `id=taskBrowserHeading` `History`; `press id=calendarEntry` returns; `press id=manageCategories` opens Categories; `press id=calendarEntry` returns; `press "label=Open Settings"` opens Settings; `press id=calendarEntry` returns; `press id=todayTab` shows `id=todayTaskList`.
- **Guards.** Start a task edit from a row's `…` > Edit, then `value id=calendarEntry` reports `[disabled]` and a press leaves the list. Cancel the edit; repeat with Delete… (before confirming) and with a category rename in the manager. Calendar becomes enabled again after each is cancelled.
- **Week grid.** `find "id^=scheduleDayHeader-"` lists seven headings Monday to Sunday labeled `Monday 16 November` …, with `, today` only on today. `find "id^=scheduleBlock-"` lists one element per `schedule_blocks` row, labeled `<title>, <Weekday> <d> <Month>, HH:mm to HH:mm` (for example `Design review, Wednesday 18 November, 10:00 to 11:00`), in day then start order; compare against the `sqlite3` rows. `frame` on two blocks: the `y` difference is their start difference in minutes times the zoom (Pairing is 30 pt below Design review at 100%), overlapping blocks have increasing `x` and do not intersect, and Thursday's three overlaps are each a third of the column. Screenshot the window and check titles truncate inside their blocks without covering the time text.
- **Current time.** `value id=scheduleCurrentTime` reads `Current time, 10:00` (the fixed clock). `press id=scheduleNext`: `find id=scheduleCurrentTime` finds nothing and no blocks are listed. `press id=scheduleToday` brings both back. In Day view on another day the line is absent.
- **Zoom and appearance.** `key cmd+shift+equal` four times reaches 150% (the window grows to 1200×872, a layout of 800×581 pt): `frame id=scheduleTimeGrid` stays inside the window's frame and `frame id=scheduleNext` and `frame id=scheduleDayHeader-<Sunday>` are inside it. `key cmd+0` returns the grid to its 100% width. Switch Theme to Light in Settings and back to compare both appearances.
- **Unavailable.** `$F fail-open <run> on`, stop and launch, `press id=calendarEntry`: `id=scheduleUnavailableState` and `id=scheduleLoadMessage` show, with `id=retrySchedule`. `$F fail-open <run> off`, `press id=retrySchedule`, and `wait id=scheduleTimeGrid`. This is a simulated storage failure.
- **Read-only.** Browsing writes nothing: compare `db.txt` from `before-calendar` with a snapshot taken after navigating.

## Gotchas

- The pane's identifiers are `schedulePane`, `scheduleHeading`, `scheduleViewMode`, `schedulePrevious`, `scheduleToday`, `scheduleNext`, `schedulePlaceholder` (Month only), `scheduleUnavailableState`, `scheduleLoadMessage` and `retrySchedule`; the rail entry is `calendarEntry`. The grid is `scheduleTimeGrid`, with `scheduleDayHeader-<YYYY-MM-DD>` (AXHeading), `scheduleDayColumn-<YYYY-MM-DD>` (a container; its AX frame is the union of its blocks, not the full column), `scheduleBlock-<block UUID>` and `scheduleCurrentTime`.
- Blocks are AXUnknown elements with no action yet (the editor comes later); reach them by label (`"id^=scheduleBlock-,label~=Design review"`) because UUIDs change every run. The hour gutter and lines are drawn only and hidden from Accessibility.
- `mpax` cannot scroll. The grid opens two hours before the fixed clock; pick `--now` so the blocks you need are on screen, or read them through the AX tree, which lists off-screen blocks too.
- The 800×560 minimum and the compact rail (below 740 pt) need a window resize, which this harness cannot drive; 150% zoom gives an 800-pt-wide layout with the full rail as the closest check.
- `scheduleHeading` is one AX element whose label joins the two visible lines with ` · `.
- The view and period are kept for the session: leaving Calendar and returning shows the same view and period. They are not saved, so a relaunch starts on this week.
- Calendar does not create or refresh History, so History's first-visit day is unchanged by visiting Calendar first.
