# Task window zoom

The task window's whole content (rail, lists, composer, History, Categories and Settings) scales like page zoom in a browser. View > Zoom In (Command-plus, also Command-equals), Zoom Out (Command-minus) and Actual Size (Command-0) step through 80, 90, 100, 110, 125 and 150 percent. The choice is saved on this Mac in its own defaults key, `local.menupocket.app.taskWindow.zoom`, apart from the versioned preferences; Actual Size removes the key. The window's minimum content size grows with the zoom (800 × 560 pt times the zoom), and the window grows to it from its top-left corner when needed. A level whose minimum would not fit the screen's visible area is skipped, so Zoom In stays disabled there.

## Sub-features

- `zoom-commands`: the three View items and their shortcuts. They act only while the task window is on screen and no other MenuPocket window (Quick Add panel, a row popover) holds the keyboard; otherwise they are disabled.
- `zoom-limits`: Zoom In disabled at 150 % or when the next level does not fit the screen; Zoom Out disabled at 80 %; Actual Size disabled at 100 %.
- `zoom-persistence`: the zoom survives closing the window and relaunching; a missing or unrecognized stored value means 100 % and is not rewritten.
- `zoom-window-floor`: the raised minimum content size and growth of a smaller window.
- `zoom-interaction`: text fields, the row `…` popover anchor, drag handles and drop targets keep working at every level. Popovers and sheets are separate windows and are not scaled.

## How to get to it (user POV)

- With the task window in front, press Command-plus (or Command-equals) to zoom in, Command-minus to zoom out, Command-0 for Actual Size.
- Or choose View > Zoom In, Zoom Out or Actual Size.

## Driving it with fixture.sh + mpax

Preconditions:

- Build a fresh fixture and launch with `--seed basic`; doctor must pass. Take `$F snapshot <run> zoom-before`; `defaults.plist` has no `local.menupocket.app.taskWindow.zoom` key.
- **Baseline.** `$F ax <run> frame id=todayTab` and `$F ax <run> frame id=daybookDate`, and `$F ax <run> windows` for the window bounds. `menu-path View "Actual Size"` exits 4 (disabled).
- **Zoom in.** `$F ax <run> key cmd+equal`, then `frame id=todayTab`: width and height are about 1.1 × the baseline. `key cmd+shift+equal` twice more reaches 150 %: the frame is about 1.5 × the baseline, `windows` shows the window at least 1200 × 840 pt of content (plus the title bar), and `menu-path View "Zoom In"` exits 4. `$F snapshot <run> zoom-150`: `defaults.plist` holds `local.menupocket.app.taskWindow.zoom` = 1.5 and the screenshot shows larger, sharp text.
- **Interaction at zoom.** At 150 %, follow the add, edit and row `…` steps from [Today](today-tasks.md): `key cmd+n`, `type`, `key return` saves the row (check `db.txt`); `press "label=Actions for task: Buy coffee beans"` opens the popover next to its `…` button (screenshot); `key escape` closes it. Pointer drags are Not tested through AX.
- **Zoom out and reset.** `key cmd+0`: `frame id=todayTab` matches the baseline and the key is gone from `defaults.plist`. `key cmd+minus` twice reaches 80 %, the frame is about 0.8 × baseline, and `menu-path View "Zoom Out"` exits 4.
- **Persistence.** At a non-100 % level, `$F stop <run>`, snapshot, relaunch the same run without reseeding: `frame id=todayTab` matches the level before stopping.
- **Other window key.** Turn Quick Add on in Settings, open the panel (`$F quickadd <run>`), and check that `menu-path View "Zoom In"` exits 4 and the task window's frames do not change.

## Gotchas

- `windows` reports CoreGraphics bounds including the title bar; compare content sizes, not raw bounds.
- The window's minimum at 150 % is 1200 × 840 pt of content. On a screen whose visible area is smaller, 150 % (or 125 %) is skipped by design; record the screen size with the result.
- Use `key cmd+equal` for Command-plus on US layouts; `cmd+shift+equal` exercises the `+` key equivalent itself.
