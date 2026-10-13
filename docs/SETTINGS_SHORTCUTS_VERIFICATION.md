# Settings shortcut reference — 2026-10-12

The approved Settings layout adds a read-only Keyboard Shortcuts card between Quick Add and App. Global Quick Add and six app commands remain visible; a native More keyboard controls disclosure initially hides contextual navigation and standard commands. Existing bindings, controllers, storage, services, permissions, and the fixed Quit footer are unchanged.

## Source and build

- Checkout: `/Users/nstn/Documents/Development/menu-peek/MenuPeek`, branch `main`, starting HEAD `7fcd55b` with local Settings/reference documentation changes. The pre-existing Desktop acceptance/regression document changes are outside this task.
- Final `MenuPocket/Settings/SettingsView.swift` SHA-256: `d9b41a1ae61eda012e1e34497d6d24fcf82e053c5950819b0b5e0c4557359715`.
- Environment: macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), arm64. macOS 14 was not exercised.
- The shared `MenuPocket` scheme Debug build succeeded through the test action. The final focused run passed **86/86 tests, zero failures**: 58 `AppConfigurationTests`, 18 `AppModelTests`, and 10 `LoginItemSettingsTests`.
- The first run had two failed assertions in `testComposerKeepsNativeUndoAcrossRepeatedRequestsAndWindowReopen` (lines 1259–1260). A clean tracked HEAD snapshot passed that test alone, and the unchanged final source then passed all 86 tests in one fresh run. The initial failure's cause is unproven; it is not classified as a confirmed baseline defect or a Settings regression.
- No new unit tests mirror this read-only catalog. Independent review checks the reference against the existing handlers; native checks cover its presentation.

```bash
xcodebuild -project MenuPocket.xcodeproj -scheme MenuPocket \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/settings-shortcuts-20261012/DerivedData \
  -resultBundlePath build/settings-shortcuts-20261012/FocusedTestsRerun.xcresult \
  -only-testing:MenuPocketTests/AppConfigurationTests \
  -only-testing:MenuPocketTests/LoginItemSettingsTests \
  -only-testing:MenuPocketTests/AppModelTests test
```

Raw build/test evidence lives in ignored `build/settings-shortcuts-20261012/`: `tests.log`, `tests-rerun.log`, `FocusedTests.xcresult`, `FocusedTestsRerun.xcresult`, `baseline-undo.log`, and `BaselineUndo.xcresult`. These local paths may be absent in other checkouts.

## Native component verification

The exact component fixture used production `SettingsView`, `SettingsWindowController`, and `AppModel`. Its identity was `SettingsShortcutsFixture.app`, bundle ID `local.menupocket.settingsshortcuts.fixture20261012`, version/build 1.0/1, executable SHA-256 `010363c33d6bc4b58d1c347485af89b05b423c81ca9b7c784e3805d31fea0db8`. It ran as PID 11976 during the final session. Preferences were in memory, there was no task database, and login/hotkey services were fakes. Fixture menu commands changed only review window size or injected hotkey refusal. This is component evidence, not installed-app or real global-hotkey acceptance.

The native Computer Use tool supplied window captures at 2× scale. Normal Settings content was 560 × 440 pt (1120 × 944 pixels including the title bar). A taller 560 × 800 pt content window was used to inspect the complete card. A pointer resize from the normal window reached the actual **500 × 380 pt frame minimum**, recorded as 1000 × 760 pixels; this is distinct from the fixture's content-size shortcut.

| Case | Result | Observation and raw evidence |
| --- | --- | --- |
| Core reference and initial collapse | Pass | Global and app groups, readable keycaps, notes, and collapsed native disclosure. `native-normal-ax.txt`, `native-normal.png`, `native-dark-collapsed-ax.txt`, `native-dark-collapsed.png`. |
| Pointer disclosure and long reference | Pass | Click expanded the contextual groups; scrolling reached lower groups; a later click collapsed them. Quit stayed outside the scroll area. `native-expanded-ax.txt`, `native-expanded-bottom-ax.txt`, `native-expanded-bottom.png`, `native-final-overview-ax.txt`, `native-final-overview.png`. |
| Actual minimum-size layout | Pass | Pointer resize reached the frame minimum; collapsed and expanded states remained readable horizontally and scrollable, with Quit still visible. `native-minimum-collapsed-ax.txt`, `native-minimum-collapsed.png`, `native-minimum-expanded-ax.txt`, `native-minimum-expanded.png`. |
| Light and Dark | Pass | Existing Theme controls changed appearance; the reference remained legible in both. `native-light-enabled.png`, `native-dark-collapsed.png`. |
| Quick Add off / registered / refused | Pass on fake services | Actual switch input changed the reference from off to registered. Injected refusal kept the switch on and changed the reference to Unavailable with guidance to the existing Quick Add section. `native-normal-ax.txt`, `native-light-enabled-ax.txt`, `native-refused-ax.txt`. This does not prove Carbon registration or detection of a real collision. |
| Spoken key equivalents | Pass for AX metadata | Rows expose names, textual values such as Control-Option-N and Command-comma, and contextual hints. `native-expanded-ax.txt`. VoiceOver speech was not exercised. |
| Registration pending | Model/source verification only | Existing `AppModelTests.testQuickAddRegistrationWaitsForStartAndFollowsSavedChanges` verifies preference-on/registration-false before start. The reference maps that state to pending. Pending text was not separately observed in the running fixture. |
| Tab route to the disclosure | Could not test | Three Tab presses and Option-Tab left the AX focused element at the window. `AppleKeyboardUIMode` was 0; no macOS setting was changed. `native-keyboard-attempt-ax.txt`. |

## Handoff and cleanup

Independent review is recorded locally in `build/settings-shortcuts-20261012/review.md`; its verdict applies to this reference and its bounded verification, not a Release or production-system acceptance claim. Release/CI, the full test suite, installed-app interaction, genuine global hotkey/login behavior, and VoiceOver were not part of this session.

The temporary fixture and both Debug test hosts are stopped, unregistered at their original and resulting Trash paths, and moved recoverably to Trash before completion. Build/test results, source, and captures are retained. `cleanup.json` records exact paths and initial unregister outcomes. macOS initially retained/re-registered the Trash paths; an exact-path retry then returned zero for all three. `cleanup-retry.json` retains that result, and `cleanup-verified.json` confirms no original or Trash paths remain in LaunchServices or Spotlight and every temporary original path is absent. The main `/Applications/MenuPocket.app` remained running as PID 676 with the same executable SHA-256 before and after: `a8faea8610614534e1d5545419dc4868d9dbee27df4db1507b33416d97f9a0bf`. No installation, commit, or push was performed.
