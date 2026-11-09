# Settings and Quick Add

Settings is the right-hand pane in the reusable task window with Open at Login, Theme (System, Light, Dark), the Quick Add switch, a read-only Keyboard Shortcuts reference, app information, and Quit. When Quick Add is on, Control-Option-N in any app shows a small floating panel. Return saves the text to Today in General, without changing either tab's draft or remembered category. Escape, Command-W, clicking outside, or a second press discards it.

## Sub-features

- `settings-open` opens or reuses the Settings pane from the Daybook Settings control, Command-comma, the app menu, or the glance.
- `settings-theme` applies Light or Dark app-wide at once and keeps the choice across relaunch.
- `settings-login` shows the Open at Login status (faked as disabled in the fixture).
- `settings-shortcuts` shows the shortcut reference and the More keyboard controls disclosure.
- `quickadd-toggle` turns Quick Add on or off and saves `quickAddEnabled`.
- `quickadd-panel` saves the panel text to Today/General, updates the count, and closes the panel.
- `quickadd-discard` closes the panel with Escape without saving.

## How to get to it (user POV)

- Click Settings (`Open Settings`) in the Daybook rail, press Command-comma, or choose MenuPocket > Settings….
- Choose `Settings…` from the menu bar quick look.
- With Quick Add on, press Control-Option-N in any app.

## Driving it with fixture.sh + mpax

Preconditions:

- A fresh run launched with `--seed basic`, with the status item reading `1/4`.
- `$F snapshot <run> before` has been taken; its `preferences.json` shows `"quickAddEnabled":false` and `"theme":"system"`.

- **Open Settings.** Run `$F ax <run> press "label=Open Settings"` and `$F ax <run> wait id=settingsContent`. The same window titled `MenuPocket Tasks` keeps the sidebar and shows `id=openAtLoginToggle` (value `0`), `id=themePicker` with System selected, `id=quickAddToggle` (value `0`), the shortcut reference, and `id=quitMenuPocket`. Press `key cmd+comma` while it is open: `windows` still lists only the task window. Return with `press id=todayTab` or `press id=laterTab`. Close the shared task window with `key cmd+w` while it is the key window, or with `press subrole=AXCloseButton#N`.
- **Theme.** Run `$F ax <run> press "role=AXRadioButton,label=Dark"`. Then `$F ax <run> screenshot build/verify-menupocket/evidence/<run>/settings-dark.png "role=AXWindow,label=MenuPocket Tasks"` and the task-window screenshot are dark, and the snapshot's `preferences.json` has `"theme":"dark"`. Relaunch the run: Dark is still selected.
- **Quick Add on.** Run `$F ax <run> press id=quickAddToggle`. `value id=quickAddToggle` is `1`, `runs/<run>/fixture.log` shows `hotkey registered (fake)`, and `preferences.json` has `"quickAddEnabled":true`.
- **Panel saves.** Start a Today draft first (`press id=addTask`, `type "Half typed"`). Then run `$F quickadd <run>`, `$F ax <run> wait id=quickAddField`, `$F ax <run> focus id=quickAddField`, `$F ax <run> type "Quick added task"`, `$F ax <run> key return`, and `$F ax <run> gone id=quickAddField`. The status item reads `1/5`, `db.txt` has `Quick added task` for today in `General`, and `value id=newTaskDraft` still shows `Half typed`.
- **Panel discards.** Run `$F quickadd <run>`, `$F ax <run> type "Throw away"`, `$F ax <run> key escape`, and `$F ax <run> gone id=quickAddField`. The count and rows are unchanged.
- **Quick Add off.** Press `id=quickAddToggle` again, then run `$F quickadd <run>`. The fixture log says `hotkey press ignored: Quick Add is off`, and no panel appears.
- **Proof.** Snapshots before and after each toggle, `actions.log`, and the Settings screenshots.

## Gotchas

- The fixture never registers the real Control-Option-N with Carbon, so `$F quickadd` simulates the press. The real hotkey from another app, conflict reporting, and full-screen behavior need the installed app and a person; report them as Not tested.
- Open at Login uses a fake service that always reports disabled; pressing it fails the way a refused registration would. Real login-item registration and launch at login cannot be verified with the fixture. Never toggle it in the user's installed app to test.
- Theme changes the whole fixture, but the menu bar quick look follows the macOS appearance instead.
- `id=gearshape` is SwiftUI's automatic image identifier. Use `label=Open Settings`.
- The Quick Add panel does not activate the app. Typing still works because key events go to the fixture's PID, but a screenshot without a query captures the frontmost fixture window, not the panel. Pass `id=quickAddField` or `role=AXWindow,…` to capture the panel.
