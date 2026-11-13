# System Monospace — 2026-11-12

The requested change applies System Monospace throughout app-owned content: date rail, headings, task text, composers, buttons, popovers, History, Categories, Settings, Quick Add, menu bar count, main menus, glance and task/category drag previews. Existing sizes, weights and italic emphasis are retained. macOS owns window chrome, tooltips and system interfaces. No persistence, services or dependencies change.

SwiftUI fonts explicitly use the monospaced system design, with inherited defaults at shared view roots. AppKit uses `NSFont.monospacedSystemFont`. Theme and History filters use `SystemMonospaceSegmentedPicker`, retaining native `NSSegmentedControl` selection and accessibility while setting its font directly: SwiftUI's segmented Picker ignores its inherited font design.

The pre-existing uncommitted inline-composer implementation and Daybook recipe edits were preserved. No installation, commit or push is included.

## Verification

Agent-operated isolated fixture `20261112-231355`, seeded with `basic`, frozen at `2026-11-12T16:00:00Z`, America/Toronto. Raw evidence: `build/verify-menupocket/evidence/20261112-231355/`; source/executable hashes are in `identity.json`. The fixture uses separate SQLite/defaults and fake login/hotkey services.

| Check | Result | Evidence |
| --- | --- | --- |
| Shared-scheme Debug build and focused tests | Pass | 80 tests, zero failures: `build/system-monospace-tests.log`, `.xcresult` under `build/system-monospace-derived/Logs/Test/`. Covers AppConfiguration, MenuBarGlanceMenu and QuickAddPanel. |
| Today, rail and saved text | Pass | Snapshots 01, 10 and 15; Vietnamese text pasted into the actual field, saved with Return, observed in AX/SQLite. |
| Settings and Theme | Pass | Snapshot 03; native segments display monospace, Light selected and persisted. |
| History and native filter | Pass | Snapshots 04 and 13; Unfinished selection hides completed rows without changing saved tasks/counts. |
| Categories, composer and category popover | Pass | Snapshots 06–08. |
| Later and task actions | Pass | Snapshots 12 and 16. |
| Quick Add | Pass (simulated hotkey) | `quick-add.png`, snapshot 11; panel saves fictional text with Return and count becomes 1/7. |
| Menu count and glance | Pass | `status-count.png`, `glance.png`; monospace rows/category labels/actions and correct counts. |
| Light/Dark appearance | Pass | Light screenshots 03 onward; Dark/System screenshot 01 and glance. |
| Restart preservation | Pass | Snapshots 14 stopped and 15 relaunched have byte-identical `db.txt` and decoded preferences; `build/system-monospace-preservation.json`. |
| Native segmented font/selection/disabled behavior | Pass | Independent offscreen probe: `build/system-monospace-segment-review.swift` and `.log`. |
| Actual Tab/arrow selection of native segments | Not tested | AX focus requests did not move first responder; CUA Tab/arrow attempts also stayed on SwiftUI controls. Independent same-environment baseline/new comparison found `canBecomeKeyView=false` with Full Keyboard Access off in both controls. No system preference was changed. |
| Minimum-size pointer resizing, physical drag previews, VoiceOver, production identity and real login/global hotkey | Not tested | No change to these integration boundaries; fixture observations do not establish them. |

Three fictional task additions are intentional. The first CUA typing attempt omitted Vietnamese accents; the subsequent clipboard-paste path preserved them. Earlier failed AX typing/focus attempts and mislabeled snapshots 02/05/09 remain in the raw evidence and are not passing keyboard/save evidence. Successful saved text is recorded from snapshot 10 onward.

## Independent review and cleanup

The independent `monospace_review` agent did not author the implementation. Its exact-snapshot report is `build/system-monospace-review.md`, with scoped patch and source hashes in `build/system-monospace.patch` and `build/system-monospace-source.json`.

Initial sandbox build `20261112-230936` could not run Swift macros. Retrying outside the sandbox compiled successfully. That incomplete bundle and superseded fixture `20261112-231003` were stopped/trashed/unregistered using the verification harness; their retained `cleanup.txt` files record completion. Final fixture `20261112-231355/cleanup.txt` confirms no original bundle path, LaunchServices registration, defaults suite or process remains. `build/system-monospace-host-cleanup.txt` confirms the shared-scheme test host was trashed/unregistered and the user's existing Debug bundle remains present. Evidence and `.xcresult` files were retained.

## CI compatibility correction

[PR #79's first CI run](https://github.com/nstnn/MenuPeek/actions/runs/43366463983/job/131691914478) failed to compile on Xcode 16.4 / Swift 6.1.2: the native segmented picker's Objective-C callback accessed main-actor-isolated SwiftUI state and AppKit properties from a coordinator without explicit actor isolation. The initial local checks used Xcode 27 / Swift 6.4 and did not reveal this compatibility error.

The coordinator is now explicitly `@MainActor`, matching its native UI responsibilities and the existing `NSViewRepresentable` methods. Selection, fonts, layout and persistence logic are unchanged. Follow-up verification uses an archived copy of the exact published PR plus this correction, excluding the unrelated local composer layout changes. The source identity, logs, independent review and temporary-host cleanup record are retained under `build/ci-pr79-fix/`.

Follow-up local results on Xcode 27 / Swift 6.4: all 454 regular tests passed, the native Undo regression passed separately (455 total), and the Release build succeeded. Xcode 16.4 is not installed locally, so its GitHub Actions result remains the compatibility gate after publishing the correction. This compile-time actor annotation does not change observable UI behavior; no new runtime-interface acceptance is claimed.
