# Notes MVP acceptance — 2026-09-27

TASK-011 is **open**. The real Settings window and the production Notes view/state were exercised on macOS, but the system-owned `MenuBarExtra` status item and popup were not accessible to the available UI automation. Do not treat the separate-window view checks as proof that the menu bar popup opens, dismisses, sizes, focuses, or scrolls correctly.

## Artifact and isolation

- Source revision: `2277c8395522cf29a5284b9b026fc98ecb851dd2`; no product source or test files changed during this acceptance run. The [TASK-010 regression record](NOTES_MVP_REGRESSION.md) has the passing Debug build and 86-test result.
- App check: an ad hoc signed copy of that Debug app at ignored `build/task-011/MenuPocketAcceptance.app`, with temporary bundle ID `local.menupocket.task011check`. It opened the real Settings window. The copied app was quit through Settings.
- Notes check: ignored `build/task-011/NotesAcceptance.app` compiled the repository's unchanged `DailyNotesView.swift`, `DailyNotesState.swift`, note domain, and SQLite repository into a 360 × 480 pt macOS window. Its database was `build/task-011/notes.sqlite`, separate from the user's app container. A process-only Aqua override was used for the light appearance; no system appearance setting changed. The test window was closed.
- The only remaining MenuPocket process after cleanup was the pre-existing Debug app at `build/DerivedData/Build/Products/Debug/MenuPocket.app/Contents/MacOS/MenuPocket`. The test copies were not left running. The pre-existing app and its data were not changed by the acceptance interactions.

## Observations

| Check | Result | Observation |
| --- | --- | --- |
| Empty Notes view | Pass in separate window | Date, `0/0 complete`, `No notes yet`, and `Add note` appeared. |
| Add and keyboard composer | Pass in separate window | Add focused the single text field; whitespace-only Return did not save; Return and Save added notes; Escape cancelled a draft. |
| Completion and ordering | Pass in separate window | Checking a note changed progress to `1/1`; after a second incomplete note was added, it appeared above the completed note. |
| Edit and delete | Pass in separate window | Row menu opened Edit and Delete. Editing saved changed text; Delete required confirmation; Cancel kept the note; confirmed deletion removed it and updated progress. |
| Persistence | Pass in separate window | A fresh process reopened the same isolated SQLite database and showed the saved completed note. |
| Long list and yesterday | Pass in separate window | With 21 seeded today rows, the list scrolled to its last row while header, Add action, and the red `1 unfinished item from yesterday` line stayed visible. One completed yesterday row was excluded from that count and yesterday rows did not enter today's list. |
| Storage write failure | Pass in separate window | A temporary SQLite trigger rejected an insert. The composer retained `Preserve this draft`, progress stayed `1/21`, and the inline `Could not save note. Try again.` error appeared. Removing the trigger and pressing Save stored the draft and cleared the error. |
| Light and dark appearance | Pass for separate-window view | Both rendered legible text, rows, controls, and a red yesterday line. This does not prove the menu bar popup's own appearance or geometry. |
| Real Settings and Quit | Pass in isolated app copy | Settings showed English Startup/App sections, app version, and Quit. Open at Login was unavailable and remained off; it was not toggled. Quit exited the isolated app copy. |
| Actual menu bar icon and popup | Not tested | The automation surface did not expose the `SystemUIServer`-owned status item. Opening, dismissal, popup sizing/scrolling/focus, and Settings navigation from the popup remain unverified. |
| Actual app relaunch/day rollover, VoiceOver, real login startup | Not tested | The separate-window persistence/fixture checks and automated tests do not establish these system interactions. |

The separate-window screenshots were inspected during the session but were not saved as standalone image files. The fixture app, source harness, and SQLite database remain under ignored `build/task-011/` for reruns; they are test artifacts, not product changes.

## Completion gate

Use the running checkout app's menu bar icon to inspect the actual popup in light and dark appearance. Exercise its open/close, focus, scrolling, Settings route, add/check/edit/delete, relaunch, yesterday boundary, and inline failure behavior. Record the observed result against the built app identity, then close TASK-011 only if every [Notes MVP acceptance criterion](../plan/mvp/NOTES_MVP_PLAN.md#acceptance-criteria) passes and no material defect remains. If source changes, repeat affected build, tests, and UI observations.

## Delete-flow regression — 2026-09-27

The user reported that confirming deletion closed the actual menu bar panel and left an unusable confirmation on reopening. The earlier separate-window delete check did not establish that system-hosted interaction.

`DailyNotesView` now presents confirmation inside the panel, clears pending confirmation before calling delete, and cancels it when the view disappears or the selected note leaves the daily snapshot. Cancel receives visible focus; Escape cancels. Saved-note persistence and error handling are unchanged.

- Final Debug executable SHA-256: `5b706c31fed4999a1a56763040ba0feeecf35c5dad59997d8d671bc9f4ac287a`.
- Shared `MenuPocket` scheme: 86 hosted tests passed with zero failures at 21:26 local time. Evidence: ignored `build/delete-flow-tests.log` and `build/DerivedData/Logs/Test/Test-MenuPocket-2026.09.27_21-26-30--0400.xcresult`.
- An isolated `DeletionCheck.app` compiled the final production Notes view/state/repository into a normal window, using only `build/delete-flow/notes.sqlite`. In-panel confirmation, focused Cancel, mouse cancellation, Escape cancellation, and hiding/reopening the Notes view without a stale confirmation were observed. The test note remained saved. The window was closed after verification.
- The checkout's Debug app was quit through Settings and relaunched with the final build. The real menu bar popup remained inaccessible to automation, which exposed Settings instead. Confirmed deletion in the actual popup still requires user verification; these checks do not close TASK-011.
