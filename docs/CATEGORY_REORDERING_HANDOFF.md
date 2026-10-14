# Category reordering handoff — 2026-10-13

Implementation and final automated regression are delivered. Native acceptance is **partial**: required pointer/consumer/appearance/system observations remain untested or inconclusive. TASK-011 review/documentation handoff is delivered within that partial scope. Independent whole-feature verdict is **BLOCKED** by missing native evidence, with no demonstrated implementation defect or source correction. This record does not authorize publication or installation.

[Requirements](REQUIREMENTS.md#category-reordering-contract) owns the product contract, [Architecture](ARCHITECTURE.md#category-reordering) owns state/storage/native boundaries, and [Workflow](WORKFLOW.md#category-reordering-verification) owns repeatable verification. The English [category reordering plan](../plan/category-reordering/category-reordering.md) and its raw evidence are supplemental and Git-ignored. This tracked record retains the essential identities, outcomes and limitations without requiring those local files. The older [task categories handoff](TASK_CATEGORIES_HANDOFF.md) keeps its dated results; this feature supersedes its earlier ordering assumptions without closing its unrelated acceptance gaps.

## Source and artifact identity

TASK-011 started with a clean checkout at `/Users/nstn/Documents/Development/menu-peek/MenuPeek`, branch `test/category-reorder-preservation`, HEAD `51794f913ce61c7aacd5d94e7cf2ade8a28ba077`. The feature baseline is `7fcd55b5ba385d28be4feb31f4a386178fc8e720`; the range also includes separate Settings shortcut/verification-skill work and historical install records, which are not category behavior changes. TASK-011 documentation does not change app/test source. The independent report identifies the reviewed source and documentation patch separately. All 75 app/test files still match TASK-009; no historical desktop acceptance/regression content was changed.

TASK-009 used Xcode 27.0 (27A266a), Swift 6.4, arm64 macOS 26.6.2, shared MenuPocket scheme. Its app/test manifest is `build/category-reordering/task-009/source-manifest.json`. TASK-010 started at `2ec08b3821ca7d2c66b15936b112c18a194d0fea`; its fixture-source comparison records no app/test hash differences from that manifest. Only the verification seed/recipe changed for native acceptance. Different commit IDs here do not imply a different tested app implementation.

| Removed artifact | Identity |
| --- | --- |
| TASK-009 Debug executable | SHA256 `48f3af552d791c6be112e1f74c42f191bace74553addf0cb577819a6b2e06ac3` |
| TASK-009 Release executable | SHA256 `f1e58b4cfb51238f15cf1255ef6de4bd33583d215300e1d7027bbfea9a3eabac` |
| TASK-010 native fixture | Run `20261013-164814`; bundle `local.menupocket.verify.r20261013-164814`; executable SHA256 `7fba4ad6076ec60b459451fe0588a7be8616db4495dc4225dd76bc145f295d42` |

The fixture ran from `build/verify-menupocket/runs/20261013-164814/MenuPocketVerify.app`, with SQLite at that run's `data/fixture.sqlite` and defaults suite `local.menupocket.verify.r20261013-164814.defaults`. It used the `category-reordering` seed, injected clock `2026-10-13T16:00:00Z`, America/Toronto, and fake login/hotkey services. PIDs 94416 and 96286 identify the initial and relaunched processes. Doctor confirmed the intended executable and only isolated storage open. The mpax AX driver lacked Accessibility trust; Computer Use could independently select this exact fixture and inspect its AX tree/screenshots. No permissions were changed. These are fixture-host observations, not production-sandbox or macOS 14 acceptance.

## Requirement and evidence map

REQ IDs below refer to the category reordering plan, not the numbered desktop requirements.

| Plan requirement | Implementation owner | Evidence and limit |
| --- | --- | --- |
| REQ-001 hold regions/input | [CategoryDragSource](../MenuPocket/Notes/CategoryDragSource.swift), [TaskWindowView](../MenuPocket/Notes/TaskWindowView.swift), [manager](../MenuPocket/Notes/TaskCategoryManagerView.swift) | Automated lifecycle/input checks; user-operated Today click/stationary hold/drop and Later collapsed-header drop. Final Later background and task text-selection coexistence remain unobserved. |
| REQ-002 preview/insertion | [CategoryDropRouting/Target](../MenuPocket/Notes/TaskDropTarget.swift) and source preview | User confirms Today preview/insertion and manager Work count 4; saved placements corroborated. Physical edge scrolling and committed reveal not tested. |
| REQ-003 global saved order | [TaskCategoryOption](../MenuPocket/Notes/TaskGrouping.swift), [DailyNotesState](../MenuPocket/Notes/DailyNotesState.swift) | Integrated groups/options/retained-History/reopen tests; native Today/Later/manager/picker/Move To/History and quit/relaunch. Native glance and History retained across another drop not tested. |
| REQ-004 General first | Grouping/options and UUID-only [CategoryMovement](../MenuPocket/Notes/CategoryMovement.swift) | Automated ordering; General first observed across checked consumers. An attempted General drag was not tested natively. |
| REQ-005 collapse preservation | Saved-state command and scoped category reveal | Automated success/rejected/no-op/failure preservation; native Today Work and Later collapsed Learning retention. Physical reveal remains untested. |
| REQ-006 unused/hidden categories | Full-catalog planner, UUID targets and idle manager | Automated subset/anchor cases; user-operated Unused-before-first drop with saved SQLite result. |
| REQ-007 task/defaults preservation | [SQLite repository](../MenuPocket/Notes/SQLiteNoteRepository.swift), state command | Raw `rowid,*` integration snapshots and native final task equality; drafts/defaults covered within the limits below. Task draft through an actual native drop not tested. |
| REQ-008 cancel/failure/retry | Session validation/consume-once, transaction rollback and scoped issue | Automated external/stale/duplicate/no-op/write/COMMIT cases; physical manager Escape/outside/equivalent/failure/retry corroborated by state. Main-list cancellation batch inconclusive. |
| REQ-009 mouse-only | Narrow sources and existing controls/menus | No category keyboard reorder or new menu; ordinary manager/field/Actions controls observed. Existing task movement menus remain. |
| REQ-010 guards/ownership | [presentation guards](../MenuPocket/Notes/TaskWindowController.swift), [CategoryDragSession](../MenuPocket/Notes/CategoryDragSession.swift) | Automated context/catalog/lifecycle/native reservation exclusion; user manager rename/removal guards. Main-list edit/removal and some lifecycle attempts not tested natively. |
| REQ-011 atomic rank publication | Planner/repository/state; existing schema v4 | Rank-only writes, collision-free Int64 staging, rollback/retry, no-op and History signals covered automatically. Native failed rank save rolls back exactly. |
| REQ-012 honest verification/cleanup | Test suites, verification recipe, dated evidence | Final automated results and bounded native session below; unobserved cases remain explicit. Session cleanup records retained. |

## Automated regression

TASK-009 expanded [the real-SQLite retained-History integration](../Tests/MenuPocketTests/TaskHistoryIntegrationTests.swift), using General, empty/long-name categories, sparse ranks, completed/open Today/Later rows, an older day and isolated defaults. Stale/equivalent requests preserve exact snapshots. A trigger-induced rank failure and reader-lock COMMIT failure roll back and publish nothing; fresh retries succeed. A committed reorder increments History once and the retained projection reloads current grouping. Category rowids/non-rank fields, every task field/rank, schema and defaults remain unchanged. Create/rename/remove are then exercised and accounted for separately before fresh state/repository/defaults reopen without reseeding; schema stays v4 and integrity is `ok`.

| TASK-009 check | Recorded result |
| --- | --- |
| Seven affected suites | 222 tests, 0 failures |
| First full suite | 443 tests, one scroll assertion failure in `AppConfigurationTests.testBrowserRetainsMountedComposerAndScrollThroughNativeAddCommand`: offset 644 versus 650, tolerance 1 pt |
| Unchanged isolated scroll recheck | 1 test, 0 failures |
| Final unchanged full suite | 443 tests, 0 failures |
| Debug and Release builds | Both succeeded |

The initial failure's cause remains unresolved; subsequent passes do not establish a proven environmental/pre-existing defect or fully stable scrolling. An earlier sandbox attempt failed compiling Observation macros before assertions; authorized Xcode execution passed. All outcomes remain recorded in [TASK-009 evidence](../plan/category-reordering/evidence/task-009-handoff.md), with logs/results under `build/category-reordering/task-009/`. These are historical automated checks on the identified unchanged source, not fresh TASK-011 results or physical gesture proof.

## Fresh independent review

Reviewer `/root/independent_category_review` was dispatched with no author conversation and did not author/design/fix the submitted source. The [independent report](../build/category-reordering/task-011-independent/review.md) covers the exact category diff at the baseline/HEAD above: SHA256 `7b733464421d907bda8612c31eab6712cc1c3d64baa1e66cf2492cc386de31b5`, with selected paths retained in `review-identity-after.json`. Its stable app/test manifest SHA256 is `930e00f6021002dc5d4e751837d091babde54e58698a17237059201b6eb32af4`. Current fixture entry-point and production inputs also match TASK-010's recorded hashes. Documentation additions are identified separately by the final review snapshot.

The reviewer inspected source/callers and requirement coverage, ran the full hosted Debug suite (**443/443 pass**) and Release build (**succeeded**) on unchanged source, and recomputed prior native preservation from the retained disposable SQLite backup opened read-only. Every task field/rowid equals the native baseline; stopped/relaunched database/defaults match exactly, with only the previously accounted category CRUD and collapse differences. The prior intermittent scroll test passed again unchanged; its original cause remains unresolved. Commands use the shared scheme/macOS destination with isolated derived data `build/category-reordering/task-011-independent/DerivedData-review`; logs and `full.xcresult` remain beside the report.

Whole-feature verdict: **BLOCKED — required native acceptance evidence is incomplete**. No actionable source defect was established. This verdict is preserved; successful automated/data checks do not upgrade it to READY. TASK-011 may complete a truthful review/documentation handoff with the remaining acceptance gate below.

Removed review Debug/Release executables have SHA256 `d10b56e82e465792c255daf00b0f6e5b7d17994745d76c9a6e82b404c7d7c1ce` and `3a5222fad8243067768986f2715d3c7683973ce70bcf02334f5c225eed7254a8`. They were not the native-observed TASK-010 artifact and establish no new physical-interface result.

## Native session

The [TASK-010 matrix](../plan/category-reordering/evidence/task-010-acceptance.md) separates user-operated physical gestures from agent AX/SQLite/defaults observations. Its raw evidence is under `build/verify-menupocket/evidence/20261013-164814/`.

| Native scenario | Recorded outcome |
| --- | --- |
| Today | User confirms disclosure/stationary hold, preview/insertion and Errands-before-Work drop; saved order Errands/Work/Unused/Learning and unchanged task tables corroborated. Work stayed collapsed. |
| Later | A collapsed Learning header retry saved Learning/Errands/Work/Unused and retained collapse. The earlier no-change batch is inconclusive; background gesture not separately confirmed. |
| Manager | Unused moved first; preview Work counts all 4 assignments. Subsequent failure/retry preserves fresh `Keep this draft` and field focus. User intentionally renamed Work and created Pending category; these are separate CRUD changes. Initial draft preservation was inconclusive because Create consumed it. |
| Manager cancellation/guards | User confirms Escape, outside release, equivalent placement, rename and removal-confirmation rejection; resulting catalog/draft and idle state corroborated. |
| Failed save/retry | Isolated trigger-induced ABORT preserved exact category/task snapshots and showed the reorder error. Removing the trigger and repeating the physical move saved Pending category/Unused/Learning/Errands/Rename Work; error cleared, draft/focus retained. |
| Ordinary controls/consumers | Agent checked Done, checkbox/progress with restoration, edit typing/Cancel, Actions, picker/Move To and current History grouping. This does not prove pointer text selection, an existing task drag, or retained History across a subsequent reorder. |
| Native quit/relaunch | Original process exited; same artifact/clock/database relaunched without reseeding. Exact categories/tasks/defaults matched stopped snapshot; Today/Later collapse, counts and manager order visible. |

Final raw notes/later_tasks equal the initial baseline in every field and rowid. Category differences are ranks plus the explicitly exercised rename/create. Schema v4, integrity `ok`, no failure trigger remains; AppPreferences JSON is unchanged. Collapse differences are the intentional Today Work and Later Learning toggles. Composer input was cancelled before History; task-draft retention through a native category drop remains untested.

One agent `drag` returned in under one second with no saved/AX change. The adapter could not compose a documented held-button sequence for the threshold; the attempt is inconclusive, not a demonstrated defect or native Pass. The user stopped further manual checks, so no repeated physical session is implied by this handoff.

## Remaining acceptance gate

- **Not tested/inconclusive pointer cases:** Later empty-background hold, early movement on the final fixture, tall-group/manager edge scrolling and feedback refresh, committed reveal, main-list cancellation/no-op/outside release, General attempted drag, task text selection and existing task pointer drag after reordering.
- **Not tested native guards/preservation/consumers:** main-list edit/removal/data/lifecycle guards, task draft across a native drop, glance order, and History retained across another native reorder. Automated coverage is narrower than physical observation.
- **Not tested host/system/layout:** Light appearance, real minimum-size window and all affected hit regions, macOS 14 runtime, VoiceOver, production identity/App Sandbox, genuine login/hotkey/day/wake/time-zone/display changes, and production-data upgrade. Dark/wrapped manager controls were observed only in the identified fixture.
- **Stability caveat:** the initial intermittent hosted scroll failure remains unexplained despite passing unchanged rechecks.

No observed TASK-010 case established a new product defect. Missing required observations keep whole-feature acceptance partial; the documentation/review card can finish while preserving those gaps. Local checks do not establish remote CI, and no publication/install is included in TASK-011.

## Cleanup and handoff scope

TASK-009 removed/unregistered every created Debug/Release host after its session, retaining identities/results. TASK-010 cleaned failed run `20261013-164744` and successful run `20261013-164814`: fixture processes exited, original paths disappeared, temporary defaults were removed and LaunchServices exposed no runnable session copy. Bundles were moved to Trash and unregistered; Trash was not emptied. Logs and final isolated database backup remain evidence. The main `/Applications/MenuPocket.app`, production storage/preferences, permissions and real login/hotkey services were preserved.

TASK-011 changes current documentation and English plan status only; independent review required no source repair. It preserves the dated desktop acceptance/regression records and performs no commit, push, PR, installation or production-data experiment. Coordinator checks resolve local links/anchors across eight tracked documents and the English plan/evidence, validate all 11 plan cards with acyclic dependencies/traceability, and pass `git diff --check`. Final independent documentation inspection is recorded with its content identity in the review report. TASK-011 source/test edits: none; changed files are this handoff, Requirements, Architecture, Workflow, README, the documentation index, the original category handoff amendment and the AGENTS document-map entry, plus the ignored English plan/evidence.

The independent review also cleaned its own Debug/Release products: original/Trash registrations and Spotlight paths are absent, no session process remains, and main app PID 28854/executable SHA256 `9b52c6a7924d4e5de13382a2f77e63738490d14a9fd6146026b3e14eff14fb17` stayed unchanged. Review cleanup evidence is `build/category-reordering/task-011-independent/cleanup.json`; source/logs/results remain.
