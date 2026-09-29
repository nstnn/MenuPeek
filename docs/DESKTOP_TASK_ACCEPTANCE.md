# Desktop task interface acceptance — 2026-09-29

**Status: partial; full feature acceptance is Blocked.** This tracked record imports the Task 9 running-Release observations. The task window, native text commands, cancellation, Settings, Quit and observed saved-data relaunch passed within the scopes below. System menu bar/Dock access and safe fixture interaction were denied; material observations remain open.

The user authorized Task 10 documentation updates while asking that Task 9 be assumed completed. Task 9's actual report became available during the update and records partial acceptance. Documentation synchronization can finish under that authorization without declaring those checks passed. No tests were created or run, app rebuilt, or app/system interaction performed by the documentation update. [Desktop regression](DESKTOP_TASK_REGRESSION.md) retains the separate Task 8 automated evidence.

## Artifact and observation identity

- Task 9 source: clean tracked `main`, `52cd8e8f3a11d5e2c60494f1622978c6d8299ffe`.
- Running product: `build/desktop-task-management/task-008/Release/MenuPocket.app`; bundle ID `local.menupocket.app`; version `0.1.0` / build `1`; minimum macOS `14.0`; regular-app metadata.
- Executable SHA-256: `b88c9444017b160ff61e8e82efefa27dc56a6b34ae142ab82a75f7246a95fd98`.
- Task 9 checked the recorded source manifest and every retained Release bundle file against Task 8; no product source/test/configuration changed or rebuilt for that acceptance card. Its identity was recorded at `2026-09-29T16:08:20.527123+00:00`.
- Computer Use selected the full retained Release path. Screenshots were inspected in that session's tool trace; no standalone screenshot files were exported. The written observations below are the retained portable evidence.

Early observations overlapped Debug and Release copies with the same bundle identifier, so they do not establish exact window identity. Later native text/cancellation/Settings/persistence observations were repeated during a confirmed single-copy Release interval, PID `26304`. A process inventory after Command-Q contained no MenuPocket process; relaunch PID `27645` showed the same existing rows. Re-querying a quit app through Computer Use could restart it, so such reinspection was not treated as a failure to quit.

The early live snapshot was empty with two unfinished tasks from yesterday. Later reads showed two existing current-day tasks; the run did not seed/save those rows or establish their provenance/change timing. Persistence comparisons use the later single-copy snapshot. No byte-for-byte claim about the production database or historical preference/onboarding state is made.

## Imported interface results

| Check | Result | Observation and scope |
| --- | --- | --- |
| Explicit Release launch/relaunch | Pass | Actual Today window appeared from the retained app, including after verified process exit. |
| Empty/populated Today snapshots | Pass for observed snapshots | English date, `0/0`, No tasks yet, informational yesterday count; later two existing rows with UUIDs, unchecked controls, English Edit/Delete labels and `0/2`. No saved action was performed. |
| Command-N and native text editing | Pass | Composer focus; Command-A/C/X/V and Command-Z/Shift-Command-Z operated field text. Saved-task undo is not claimed. |
| Whitespace input and new-draft cancellation | Pass | Whitespace left Save disabled and rows/count unchanged. Escape removed the composer and returned focus to Add. Nonblank temporary drafts were cancelled without saving. |
| Edit cancellation | Pass | Existing text populated the edit field; competing actions disabled; Escape preserved row/text/count and restored Edit focus. Saved editing remains unverified. |
| Delete confirmation/cancellation | Pass | Inline confirmation initially focused Cancel; Escape preserved both rows and `0/2`. Confirm Delete was not pressed. |
| Settings routes/reuse and Command-W | Pass for visible behavior | Task-window action and Command-comma opened English Settings; repeated requests retained the displayed surface; Command-W returned to Tasks. Exact controller identity is hosted-test evidence. |
| Keyboard focus order | Pass for exercised controls | Tab moved from Add to Settings then the first task checkbox; cancellation restored usable focus. Exhaustive traversal and VoiceOver were not observed. |
| Dark appearance and native zoom | Pass for exercised snapshots | Tasks/Settings were legible; zoom enlarged and restored the window while retaining its main areas. Minimum-size/long-content/light checks remain open. |
| Command-Q process exit | Pass | Release PID `26304` exited and the following inventory had no MenuPocket process. Status-item removal is separately blocked. |
| Settings Quit process exit | Pass | Release PID `25091` disappeared after Settings Quit. Later tool reinspection could restart the target; those restarted processes were subsequently stopped. |
| Saved tasks across actual Quit/relaunch | Pass for observed rows | Release PID `27645` showed the same two UUIDs, text, order, unchecked completion values, `0/2`, and yesterday count after the single-copy exit. No production test rows were added. |
| Actual status item: primary click, icon/count, width, removal | Blocked | Computer Use was not approved to use SystemUIServer. No alternate OS-input route bypassed the denial. |
| Dock/Command-Tab and status/Dock reopen/restore | Blocked | Computer Use was not approved to use Dock. App-window observations do not prove these routes. |
| Sustained close-all/minimized interval and exact same-window restore | Not tested to required scope | Close/minimize requests were exercised, but accessibility reinspection did not establish the interval, visible progress, or exact native window identity. |
| Saved CRUD/live count changes, read retry and failed-write recovery | Blocked for safe fixture verification | The fixture compiled, but Computer Use was not approved to use Task9AcceptanceFixture. Production rows were not mutated to seed scenarios. |
| All-completed, long-list/text, minimum size, light appearance | Not tested | Prepared fixture scenarios could not be exercised through the authorized interface. |
| Genuine closed-window day transition/wake | Not tested | No genuine transition/qualifying wake observed; injected-notification results remain automated support. |
| VoiceOver/additional displays | Not tested | No session or additional hardware coverage recorded. |
| Genuine login startup | Not tested | Settings reported Open at Login unavailable/off. No stable installed/authorized login copy or real login was exercised; registration was not changed. |

## Fixture isolation and cleanup

The prepared fixture used unchanged production owners/views, a separate database under `build/desktop-task-management/task-009/fixture.sqlite`, separate defaults suite and bundle ID `local.menupocket.task009.acceptance`, and a fake unavailable login service. It was non-sandboxed, so it could not establish production sandbox identity or actual login behavior. The authorized fixture compiler retry succeeded, but interface access was denied before an accepted launch; no fixture process/database was left running/created. Build success is not interface acceptance.

Task 9 cancelled temporary drafts and confirmation, made no saved add/completion/edit/confirmed-delete, changed no login registration or system appearance, and performed no installation/publication. Retained Release processes were quit. The original Debug path was restored using its existing on-disk build, final PID `28039`, with both rows visible and no composer/confirmation. Restoring the former process's in-memory revision is not claimed.

## Remaining acceptance gate

1. Obtain approved Computer Use access to SystemUIServer, Dock and the isolated fixture, or retain exact human observations for their required interactions. Do not bypass denied access.
2. Against one identified final Release process, observe actual status rendering/count changes/click/removal, Dock/Command-Tab, same-window reopening, and sustained closed/minimized intervals.
3. With isolated data, observe saved add/complete/uncomplete/edit/delete, failure/retry/draft recovery, all-completed/long-content/minimum-size states, and light appearance.
4. Observe genuine day/wake and login behavior when the environment permits, and record the available VoiceOver/display coverage. Keep unavailable checks explicit.

Full feature acceptance requires material interface requirements to pass on the final artifact. A product fix requires affected automated checks, rebuilding, replacement identity, and renewed affected interface observations. Documentation completion does not close Task 9 or the outstanding Task 1/6/7 system gaps.

## Local provenance

The imported narrative is `plan/desktop-task-management/evidence/task-009.md`. Local identity/process records and fixture preparation are under `build/desktop-task-management/task-009/`, including `identity.json`, `process-single-release.txt`, `process-after-release-quit.txt`, `process-relaunch.txt`, and `process-final.txt`. These directories remain Git-ignored; the results, identity, limits and pending gate above remain available in this tracked record.

The [historical Notes MVP acceptance](NOTES_MVP_ACCEPTANCE.md) describes the superseded compact panel and retains its original limitations. It does not replace this desktop acceptance record.
