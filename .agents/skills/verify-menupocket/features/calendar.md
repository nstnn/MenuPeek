# Calendar

Calendar is a sidebar destination beside Today and Later. It replaces only the right content column with a pane that names the visible period, offers a Day/Week/Month switch (Week first), and moves with Previous, Today and Next. Calendar opens from Today or Later and leaves the selected list as it was. The time grid, block editor and month cells are not built yet: the body shows a one-line summary of the loaded period (`No blocks this week`, `2 blocks this week`). A failed read shows Calendar is unavailable with the period's message and Retry, never an empty calendar.

## Sub-features

- `calendar-entry`: the rail footer lists Calendar, a thin rule, History, Categories and Settings, in that order. Calendar uses the calendar symbol; History uses a clock symbol. The active entry is accent-colored, and History is not highlighted while Calendar is open.
- `calendar-route`: Calendar opens from Today and from Later, keeps the rail mounted, and leaves the Today/Later selection unchanged. Today, Later, History, Categories and Settings each leave it. Command-N and reopening the window from the menu bar return to the list.
- `calendar-guards`: like History, Calendar is disabled while a task edit, a task deletion confirmation, a category rename or a category removal confirmation is open. An idle category manager may be left for Calendar.
- `calendar-header`: the heading reads the period: Week `November 2026 · Week 47`, Day `November 2026 · Wednesday, November 18, 2026`, Month `November 2026`. Previous, Today and Next move by the current mode's unit; the view switch keeps the selected or current day in view.
- `calendar-unavailable`: a failed read shows `Calendar is unavailable`, `Could not load this week. Try again.` (day/month in those modes) and Retry.

## How to get to it (user POV)

- Click Calendar at the bottom of the task window's rail, from Today or from Later.
- Leave by choosing Today or Later in the rail switch, or History, Categories or Settings.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic` (no Calendar blocks are seeded yet). Fix the clock with `--now` when comparing heading text against a date. Take `$F snapshot <run> before-calendar`.

- **Sidebar order.** `$F ax <run> frame id=calendarEntry`, `frame id=taskHistoryEntry`, `frame id=manageCategories` and `frame "label=Open Settings"` have increasing `y`. `value id=calendarEntry` is labeled `Open Calendar`. The rule between Calendar and History is drawn only (not in the AX tree); confirm it in the screenshot.
- **Open from Today.** `$F ax <run> press id=calendarEntry`, then `wait id=schedulePane`. `value id=scheduleHeading` names the current week (`… · Week NN`), `value id=scheduleViewMode` reads `Week`, and `value id=schedulePlaceholder` reads `No blocks this week`. `value id=daybookDate` and `value id=todayProgress` still answer, and `value id=todayTab` is still selected. Snapshot `calendar-week`.
- **Navigate.** `press id=schedulePrevious`: the heading's week number drops by one. `press id=scheduleNext` twice: one week ahead. `press id=scheduleToday`: back to the first heading. Each heading change is the proof; `value id=schedulePrevious` is labeled `Previous week`.
- **Switch view.** `id=scheduleViewMode` is a radio group whose value is the current view. Choose a segment with `press "role=AXRadioButton,label=Day"` (or `Month`, `Week`); these are the only radio buttons with those labels in the window. Day: the heading includes the full date (`November 2026 · Wednesday, November 18, 2026`) and `id=schedulePrevious` is labeled `Previous day`. Month: the heading is the month and year only, and the placeholder reads `No blocks this month`. Return to Week.
- **Open from Later.** `press id=laterTab`, `press id=calendarEntry`, `wait id=schedulePane`. `value id=laterTab` stays selected. `press id=laterTab` returns to Later's list (`wait id=laterTaskList`).
- **Leave through every entry.** From Calendar, `press id=taskHistoryEntry` shows `id=taskBrowserHeading` `History`; `press id=calendarEntry` returns; `press id=manageCategories` opens Categories; `press id=calendarEntry` returns; `press "label=Open Settings"` opens Settings; `press id=calendarEntry` returns; `press id=todayTab` shows `id=todayTaskList`.
- **Guards.** Start a task edit from a row's `…` > Edit, then `value id=calendarEntry` reports `[disabled]` and a press leaves the list. Cancel the edit; repeat with Delete… (before confirming) and with a category rename in the manager. Calendar becomes enabled again after each is cancelled.
- **Unavailable.** `$F fail-open <run> on`, stop and launch, `press id=calendarEntry`: `id=scheduleUnavailableState` and `id=scheduleLoadMessage` show, with `id=retrySchedule`. `$F fail-open <run> off`, `press id=retrySchedule`, and `wait id=schedulePlaceholder`. This is a simulated storage failure.
- **Read-only.** Browsing writes nothing: compare `db.txt` from `before-calendar` with a snapshot taken after navigating.

## Gotchas

- The pane's identifiers are `schedulePane`, `scheduleHeading`, `scheduleViewMode`, `schedulePrevious`, `scheduleToday`, `scheduleNext`, `schedulePlaceholder`, `scheduleUnavailableState`, `scheduleLoadMessage` and `retrySchedule`; the rail entry is `calendarEntry`.
- `scheduleHeading` is one AX element whose label joins the two visible lines with ` · `.
- The view and period are kept for the session: leaving Calendar and returning shows the same view and period. They are not saved, so a relaunch starts on this week.
- Calendar does not create or refresh History, so History's first-visit day is unchanged by visiting Calendar first.
