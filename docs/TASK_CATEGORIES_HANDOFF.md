# Task categories handoff — 2026-10-02

**TASK-012 documentation and partial handoff: complete. Category feature acceptance: partial; TASK-011 remains open.** The user separately requested this documentation task while interface acceptance was incomplete. This record consolidates existing evidence; it does not turn unavailable observations into passes.

The implemented product contract is [REQ-014 and Category contract](REQUIREMENTS.md#category-contract), including optional categories, grouping/order, collapse/counts, atomic drafts, all-days removal, and recovery. [Architecture](ARCHITECTURE.md) owns the state/storage boundaries and additive schema v2; [Workflow](WORKFLOW.md#category-verification) owns verification, preferences isolation, and [first real-data upgrade preparation](WORKFLOW.md#schema-v4-upgrade-preparation). [README](../README.md#use-the-today-window) provides usage.

## Verified source and artifacts

Verification baseline: repository `MenuPeek`, branch `main`, HEAD `7be53da0c4fd3cb5a64bf381ecb15afb5103ddff`, plus the then-uncommitted long-name removal layout repair and documentation changes. The repaired `MenuPocket/Notes/TaskCategoryManagerView.swift` SHA-256 is `73406faf370270262ab9b13259108ebec42ab289844362373b5bb3a793d41a98`. TASK-012 changes documentation and ignored plan status only; the repair's 49 Swift/project/scheme/entitlements inputs still match `build/category-fix-20261002/source-hashes.json`.

The latest Debug/Release builds use Xcode 27.0 (`27A266a`) on macOS arm64, shared scheme `MenuPocket`. Both production-identity bundles use `local.menupocket.app`, version `0.1.0`, build `1`, under `build/category-review-20261002/DerivedData/Build/Products/{Debug,Release}/MenuPocket.app`. They were built and signature-checked; they were not launched against production data for category acceptance.

| Latest artifact | Executable SHA-256 |
| --- | --- |
| Debug MenuPocket | `e3524a6d5316b00bfbcdd125ed05fa0f5bdc4cb5e4fdba3e6d8fbe4139833128` |
| Release MenuPocket | `e7dc1dcfcdec54e564dcd95bb9a92b0316d798df4293242edd9b7db79d8a302d` |
| CategoryFixFixture | `6e5cddd4ed25d2b050341de8665948bd0fc0ba1782d2be05018d18d2838a13c7` |

The rebuilt native fixture is `build/category-fix-20261002/CategoryFixFixture.app`, bundle `local.menupocket.fix20261002.fixture`. It uses production views/state/controller/delegate/Settings/status item, a separate SQLite file at `build/category-fix-20261002/fixture-data/mixed/notes.sqlite`, and defaults suite `local.menupocket.fix20261002.categories.mixed`. It is non-sandboxed, injects October 2 as the local day, and uses fake login/hotkey services. Screenshots were inspected inline through Computer Use, without saved image files. No live PID was captured for these interactions; identity rests on the launched absolute path, bundle/hash, and matching fixture UUIDs.

## Automated evidence

| Verification | Recorded outcome and scope |
| --- | --- |
| Integrated TASK-010 | **Pass:** 134/134 focused tests, 219/219 full hosted tests with none skipped, Debug/Release builds and signatures. Six isolated SQLite scenarios passed headless seed and separate-process reopen, including legacy v1-to-v2. These are automated fixture checks. |
| Subsequent independent feature review | **Pass for storage probes:** reader locks forced SQLITE_BUSY at COMMIT for all seven repository mutations; full snapshots rolled back and retries succeeded. Writer contention/retry and reopen also passed. The review found a long-name layout defect and stale docs, and required remaining interface acceptance. |
| After the removal layout repair | **Pass:** fresh Debug hosted build/test, 219/219 with none skipped; Release build; Debug/Release/fixture signatures. Result: `build/category-fix-20261002/Fix-tests.xcresult`; logs: `tests.log` and `release-build.log` in that directory. |
| Independent repair review | **READY for the repair scope only:** source/artifact hashes, retained xcresult, saved-data comparisons, and scoped native evidence reconciled. This verdict preceded TASK-012's additional documentation and does not approve full feature acceptance or a release/merge. |

[TASK-010 regression](DESKTOP_TASK_REGRESSION.md#integrated-category-regressions--task-10-2026-10-02) and [repair regression](DESKTOP_TASK_REGRESSION.md#category-removal-repair-2026-10-02) retain commands, toolchain, identities, preservation, and test boundaries. The independent reports and COMMIT probe remain under ignored `build/category-review-20261002/` and `build/category-fix-20261002/fix-review.md`. Tests use isolated repositories/defaults; the Debug host skips production delegate initialization. No remote CI result or macOS 14 runtime check is established by the local Xcode 27 results.

## Native interface evidence

Earlier Task 7–9 user-reported in-memory fixture passes and the original Task 11 preflight/untouched-seed relaunch remain in [Desktop acceptance](DESKTOP_TASK_ACCEPTANCE.md). They retain their original source, identity, and limitations.

The subsequent review's SQLite fixture, before the layout repair, was `build/category-review-ui-20261002/CategoryReviewFixture.app`, bundle `local.menupocket.review20261002.fixture`, executable SHA-256 `cb00504a42fddba82a2132d55553a02d52ade4b50474ec5fdd68c594c24fdeff`. It used `build/category-review-ui-20261002/fixture-data/mixed/notes.sqlite`, defaults `local.menupocket.review20261002.categories.mixed`, and fake services without a sandbox.

Direct Computer Use observations on that earlier artifact passed reserved-name rejection, Reading creation/picker/add with Return, remembered Reading, School collapse with unchanged counts, and simulated new-task write/read failure recovery retaining text/category. Saved Reading data, remembered Reading, and collapsed School survived actual Command-Q, confirmed process exit, and relaunch without reset. Stopped/relaunched snapshots matched all saved fields, category preferences, and artifact identity; the new draft was blank and remembered Reading. Raw `stopped.json`, `relaunched.json`, and `relaunch-comparison.json` remain in that fixture directory. The standalone Command-W observation was ambiguous and is not a native Pass. This artifact reproduced the 775-character removal defect; these earlier results are not promoted to the rebuilt fixture.

The [rebuilt fixture observations](DESKTOP_TASK_ACCEPTANCE.md#category-removal-repair-2026-10-02) establish:

| Check on CategoryFixFixture | Result |
| --- | --- |
| Long-name confirmation at 480 × 360 in dark/system appearance | **Pass:** complete 775-character name reachable by scrolling; four-task all-days notice and both actions remain visible. Cancel starts focused. |
| Escape and retry keyboard flow | **Pass:** Escape returns to the manager with Remove focused; fresh confirmation, Tab to Remove Category, and Return work. |
| Failed removal | **Pass:** inline error, unchanged complete saved snapshot, and fresh confirmation required after failure. |
| Successful all-days removal | **Pass:** only the target category and its four assignments across three days change. All eight tasks retain UUID, rowid/order, text, day, timestamps, and completion. |
| Visible saved result | **Pass:** Today remains 1/6; General is 1/3 with Task 1, Task 5, Task 6 in original relative order. |
| Changed-data/preferences Quit/relaunch after repair | **Not tested:** the earlier artifact's relaunch result does not establish this rebuilt artifact's integrated acceptance. |

Raw `before-removal.json`, `after-failure.json`, `after-removal.json`, and `removal-comparison.json` in `build/category-fix-20261002/` support the two complete-snapshot comparisons. No production data was seeded or upgraded, and no real login/hotkey registration was changed.

## Remaining TASK-011 gate

Final integrated interface acceptance must identify its final source/artifact and record the following outcomes:

- **Not tested on the rebuilt artifact:** the complete create/duplicate/rename/add/edit/reassign/category-only flow set; failed edit/category-command and stale category/target/day recovery; manager/draft guards, close/reopen, destination expansion, and empty-category behavior.
- **Not tested on the rebuilt artifact:** changed saved data and both presentation preferences across actual process exit/relaunch, with complete stopped/relaunched comparisons and visible recovery/new-draft behavior.
- **Not tested beyond the scoped repair:** light/dark and minimum-size layouts, many/empty/General-only/all-completed states, long task text, complete keyboard/native editing/focus traversal, Settings reuse, and VoiceOver when available.
- **Open production/system scope:** production-identity menu bar/Dock/window routes and first real-data upgrade/backup preparation. The earlier read-only preflight found schema v1 and 15 tasks; it did not prepare a backup or launch a v2 production build. Follow the workflow and then-authorized scope before that first launch.

Genuine day/wake/login and additional-display observations retain their historical **Not tested/Blocked** scope in Desktop acceptance and require separate evidence. Injected clocks, fake services, signature checks, and successful fixture data comparisons do not close those gaps. No missing evidence here is itself a demonstrated code defect.

## Handoff status

| Plan work | Current status |
| --- | --- |
| TASK-001–009 | Category domain, storage, state, preferences, groups, composer, and manager implemented. Earlier scoped evidence retained. |
| TASK-010 | Automated integration complete; latest source repair also has passing automated verification above. |
| TASK-011 | **Partial:** scoped native passes available; material integrated/production observations remain open. |
| TASK-012 | **Complete for documentation and this partial handoff**, as separately requested. Requirements, architecture, workflow, README, index, and AGENTS document map agree. Full feature acceptance remains dependent on TASK-011. |

TASK-012 reviewed local document links/anchors and source consistency, checked source/configuration and historical evidence hashes unchanged, and passed `git diff --check`. It did not rebuild, rerun tests, operate an app, alter saved data, commit, push, or create a PR. The dated desktop/MVP records remain unchanged by this task. Raw logs, bundles, and local plans are Git-ignored; the essential identities, outcomes, and remaining gate are retained above so this handoff remains understandable in another checkout.
