import AppKit
import Observation

enum HistoryReadError: Error, Equatable {
    case terminated
}

enum DailyNotesIssue: Equatable {
    case load
    case add
    case complete
    case edit
    case delete
    /// Reordering or reassigning a Today task.
    case move
    /// Transferring a Later task to Today.
    case moveToToday

    var message: String {
        switch self {
        case .load: "Could not load notes. Try again."
        case .add: "Could not save note. Try again."
        case .complete: "Could not update note. Try again."
        case .edit: "Could not save edit. Try again."
        case .delete: "Could not delete note. Try again."
        case .move: "Could not move task. Try again."
        case .moveToToday: "Could not move task to Today. Try again."
        }
    }
}

enum CategoryNameIssue: Equatable {
    case invalid(TaskCategoryNameError)
    case duplicate

    var message: String {
        switch self {
        case .invalid(.blank): "Enter a category name."
        case .invalid(.multiline): "Category names must use one line."
        case .invalid(.reserved): "General is reserved for tasks without a category."
        case .duplicate: "A category with this name already exists."
        }
    }
}

enum CategoryCommandIssue: Equatable {
    case create
    case rename
    case reorder
    case remove
    case usage
    case notFound
    case orderExhausted

    var message: String {
        switch self {
        case .create: "Could not create category. Try again."
        case .rename: "Could not rename category. Try again."
        case .reorder: "Could not reorder categories. Try again."
        case .remove: "Could not remove category. Try again."
        case .usage: "Could not count this category's tasks. Try again."
        case .notFound: "This category is no longer available."
        case .orderExhausted: "No more categories can be created."
        }
    }
}

/// The app's single source of saved Today and Later data. Drafts remain local until a
/// repository write succeeds; a failed read never publishes a partial snapshot.
@MainActor
@Observable
final class DailyNotesState {
    enum AddOutcome: Equatable {
        case added
        case empty
        /// Saved data, or the chosen category, is not in the loaded snapshot.
        case unavailable
        case writeFailed
    }

    /// Unsaved edit text and the category selected for it when the edit was
    /// cancelled. The name is captured then, so it survives category removal.
    struct RecoveredEdit: Equatable {
        let text: String
        /// nil is General.
        let categoryID: UUID?
        /// nil for General, or for an ID the catalog did not contain.
        let categoryName: String?
    }

    /// Invalidate browse projections after committed writes or settled refresh
    /// attempts, including failed reads. History reads never advance this value.
    private(set) var historyRevision: UInt64 = 0

    private(set) var todayKey: String?
    private(set) var hasLoadedCatalog = false {
        didSet { if !hasLoadedCatalog { taskWindowPresentation.cancelCategoryMovement() } }
    }
    private(set) var categories: [TaskCategory] = [] {
        didSet { if categories != oldValue { taskWindowPresentation.cancelCategoryMovement() } }
    }
    private(set) var notes: [Note] = []
    private(set) var yesterdayIncompleteCount = 0
    private(set) var continuationMessage: String?
    private(set) var continuationFailed = false
    private(set) var hasLoadedToday = false
    private(set) var readIssue: DailyNotesIssue?
    private(set) var taskIssue: DailyNotesIssue?
    private(set) var categoryNameIssue: CategoryNameIssue?
    private(set) var categoryIssue: CategoryCommandIssue?
    /// Reorder failures do not replace name/CRUD errors or task errors.
    private(set) var categoryReorderIssue: CategoryCommandIssue?

    private(set) var laterTasks: [LaterTask] = []
    private(set) var hasLoadedLater = false
    private(set) var laterReadIssue: DailyNotesIssue?
    private(set) var laterTaskIssue: DailyNotesIssue?

    /// Keep task-write errors through a failed read and its successful retry.
    /// Existing views still consume the load error first through this property.
    var issue: DailyNotesIssue? { readIssue ?? taskIssue }
    var laterIssue: DailyNotesIssue? { laterReadIssue ?? laterTaskIssue }

    var draft = ""
    /// The new task's category; nil is General. Independent of the edit draft.
    var draftCategoryID: UUID?
    private(set) var editingNoteID: UUID? {
        didSet { if editingNoteID != nil { taskWindowPresentation.cancelCategoryMovement() } }
    }
    var editDraft = ""
    /// The edited task's category; begins as its saved association.
    var editCategoryID: UUID?
    private(set) var recoveredEdit: RecoveredEdit?
    private(set) var refreshNotice: String?

    var laterDraft = ""
    /// The new Later task's category; nil is General. Independent of Today's draft.
    var laterDraftCategoryID: UUID?
    private(set) var editingLaterTaskID: UUID? {
        didSet { if editingLaterTaskID != nil { taskWindowPresentation.cancelCategoryMovement() } }
    }
    var laterEditDraft = ""
    /// The edited Later task's category; begins as its saved association.
    var laterEditCategoryID: UUID?
    private(set) var laterRecoveredEdit: RecoveredEdit?
    private(set) var laterRefreshNotice: String?

    var recoveredEditDraft: String? { recoveredEdit?.text }
    var laterRecoveredEditDraft: String? { laterRecoveredEdit?.text }

    /// nil means unloaded or the latest read failed; successful empty is 0/0.
    /// Write failures leave this last saved progress available.
    var availableProgress: NoteProgress? { hasLoadedToday ? progress : nil }
    var availableCategories: [TaskCategory]? { (hasLoadedToday || hasLoadedLater) ? categories : nil }
    var availableLaterTasks: [LaterTask]? { hasLoadedLater ? laterTasks : nil }
    var laterRemainingCount: Int {
        laterTasks.count { !$0.isCompleted }
    }
    var availableLaterRemainingCount: Int? {
        hasLoadedLater ? laterRemainingCount : nil
    }

    /// Today's tasks grouped for display. Group counts include collapsed rows
    /// and always sum to `progress`.
    var groups: [TaskGroup] { TaskGroup.groups(categories: categories, notes: notes) }
    var laterGroups: [LaterTaskGroup] { LaterTaskGroup.groups(categories: categories, tasks: laterTasks) }

    /// Last-used category and collapsed groups; never a source of saved categories.
    let categoryPreferences: TaskCategoryPreferences

    /// Shared with the retained window so saves revalidate the same modal guards.
    let taskWindowPresentation = TaskWindowPresentation()

    var canMoveTasks: Bool {
        !isTerminating && hasLoadedToday && todayKey == day.keys().today && editingNoteID == nil
    }

    /// Readiness never refreshes here: a stale visible context must not be
    /// silently retargeted, or alter drafts/revision on a blocked reorder.
    func canReorderCategories(in context: CategoryReorderContext) -> Bool {
        guard !isTerminating, hasLoadedCatalog, editingNoteID == nil, editingLaterTaskID == nil else { return false }
        switch context {
        case .list(.today): return hasLoadedToday && todayKey == day.keys().today
        case .list(.later): return hasLoadedLater
        case .manager: return hasLoadedToday || hasLoadedLater
        }
    }

    @ObservationIgnored private let repositoryFactory: () throws -> any NoteRepository
    @ObservationIgnored private var repository: (any NoteRepository)?
    @ObservationIgnored private let day: NoteDay
    @ObservationIgnored nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isTerminating = false

    var progress: NoteProgress {
        NoteProgress(notes: notes, for: todayKey ?? "")
    }

    var errorMessage: String? { issue?.message }
    var laterErrorMessage: String? { laterIssue?.message }

    init(
        repositoryFactory: @escaping () throws -> any NoteRepository = { try SQLiteNoteRepository() },
        day: NoteDay = NoteDay(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        categoryPreferences: TaskCategoryPreferences = TaskCategoryPreferences()
    ) {
        self.repositoryFactory = repositoryFactory
        self.day = day
        self.categoryPreferences = categoryPreferences
        for name in [Notification.Name.NSCalendarDayChanged,
                     .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observe(name, on: notificationCenter)
        }
        observe(NSWorkspace.didWakeNotification, on: workspaceNotificationCenter)
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observers.append((center, token))
    }

    /// Browser projections share this authority's civil clock and read facade.
    func yesterdayForHistory() throws -> GregorianDay { try day.historyKeys().yesterday }

    func makeHistoryState() throws -> TaskHistoryState {
        try TaskHistoryState(dailyState: self, noteDay: day)
    }

    func makeUnfinishedState() throws -> UnfinishedTasksState {
        try UnfinishedTasksState(dailyState: self, noteDay: day)
    }

    // App lifecycle consumers can refresh without creating a view.
    func startup() { refresh() }
    func windowWillOpen() { refresh() }

    func stopForTermination() {
        isTerminating = true
        taskWindowPresentation.cancelMovement()
        taskWindowPresentation.cancelCategoryMovement()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        repository = nil
    }

    func refreshIfDayChanged() {
        if day.keys().today != todayKey { refresh() }
    }

    func refresh() {
        refresh(keys: day.keys())
    }

    private func refresh(keys: (today: String, yesterday: String)) {
        guard !isTerminating else { return }
        defer {
            taskWindowPresentation.validateCategoryMovement(state: self)
            historyRevision += 1
        }
        if todayKey != keys.today {
            // Invalidate the old snapshot before asking storage for the new day.
            let hadPreviousDay = todayKey != nil
            todayKey = keys.today
            notes = []
            yesterdayIncompleteCount = 0
            hasLoadedToday = false
            invalidateEditing()
            if taskIssue != .add { taskIssue = nil }
            if hadPreviousDay {
                refreshNotice = "The date changed. Previous task actions were cancelled; unsaved text is still available."
            }
        }

        let store: any NoteRepository
        let savedCategories: [TaskCategory]
        do {
            store = try openRepository()
            savedCategories = try store.categories()
            hasLoadedCatalog = true
        } catch {
            hasLoadedCatalog = false
            hasLoadedToday = false
            hasLoadedLater = false
            readIssue = .load
            laterReadIssue = .load
            return
        }

        let categoryIDs = Set(savedCategories.map(\.id))

        do {
            let savedNotes = try store.notes(for: keys.today)
            let previousCount = try store.incompleteCount(for: keys.yesterday)
            guard savedNotes.allSatisfy({ note in
                note.categoryID.map { categoryIDs.contains($0) } ?? true
            }) else { throw TaskCategoryRepositoryError.invalidRow }
            let dailyNotes = savedNotes.filter { $0.dayKey == keys.today }
            // Cancel stale edits before replacing the catalog, which can still
            // name a removed category for recovery.
            if let editingNoteID, !dailyNotes.contains(where: { $0.id == editingNoteID }) {
                invalidateEditing()
                refreshNotice = "The edited task is no longer available. Unsaved text was kept for recovery."
            }
            todayKey = keys.today
            notes = dailyNotes
            yesterdayIncompleteCount = previousCount
            hasLoadedToday = true
            readIssue = nil
        } catch {
            hasLoadedToday = false
            readIssue = .load
        }

        do {
            let savedLater = try store.laterTasks()
            guard savedLater.allSatisfy({ task in
                task.categoryID.map { categoryIDs.contains($0) } ?? true
            }) else { throw TaskCategoryRepositoryError.invalidRow }
            if let editingLaterTaskID, !savedLater.contains(where: { $0.id == editingLaterTaskID }) {
                invalidateEditingLater()
                laterRefreshNotice = "The edited task is no longer available. Unsaved text was kept for recovery."
            }
            laterTasks = savedLater
            hasLoadedLater = true
            laterReadIssue = nil
        } catch {
            hasLoadedLater = false
            laterReadIssue = .load
        }

        reconcileSelections(available: categoryIDs)
        reconcileLaterSelections(available: categoryIDs)
        categories = savedCategories
        categoryPreferences.prune(keeping: categoryIDs)
    }

    @discardableResult
    func createCategory(name: String) -> TaskCategory? {
        categoryIssue = nil
        guard let name = validatedCategoryName(name),
              readyForCategoryWrite(), let repository else { return nil }
        do {
            let saved = try repository.createCategory(name: name)
            categories.append(saved)
            historyRevision += 1
            return saved
        } catch {
            recordCategoryError(error, fallback: .create)
            return nil
        }
    }

    @discardableResult
    func renameCategory(id: UUID, name: String) -> TaskCategory? {
        categoryIssue = nil
        guard let name = validatedCategoryName(name),
              readyForCategoryWrite(), let repository else { return nil }
        guard let index = categories.firstIndex(where: { $0.id == id }) else {
            categoryIssue = .notFound
            return nil
        }
        do {
            let saved = try repository.renameCategory(id: id, name: name)
            categories[index] = saved
            historyRevision += 1
            return saved
        } catch {
            recordCategoryError(error, fallback: .rename)
            return nil
        }
    }

    /// Counts completed and incomplete assignments across every saved day and Later.
    /// A failed usage read does not invalidate the already loaded daily snapshot.
    func categoryUsageCount(id: UUID) -> Int? {
        categoryIssue = nil
        guard readyForCategoryWrite(), let repository else { return nil }
        do {
            return try repository.categoryUsageCount(id: id)
        } catch {
            recordCategoryError(error, fallback: .usage)
            return nil
        }
    }

    @discardableResult
    func removeCategory(id: UUID) -> Bool {
        categoryIssue = nil
        guard readyForCategoryWrite(), let repository else { return false }
        guard categories.contains(where: { $0.id == id }) else {
            categoryIssue = .notFound
            return false
        }
        do {
            try repository.removeCategory(id: id)
            notes = notes.map { note in
                guard note.categoryID == id else { return note }
                return Note(id: note.id, text: note.text, dayKey: note.dayKey,
                            createdAt: note.createdAt, completedAt: note.completedAt,
                            categoryID: nil, continuedOn: note.continuedOn)
            }
            laterTasks = laterTasks.map { task in
                guard task.categoryID == id else { return task }
                return LaterTask(id: task.id, text: task.text,
                                 createdAt: task.createdAt, completedAt: task.completedAt,
                                 categoryID: nil)
            }
            let remainingIDs = Set(categories.map(\.id)).subtracting([id])
            reconcileSelections(available: remainingIDs)
            reconcileLaterSelections(available: remainingIDs)
            categories.removeAll { $0.id == id }
            categoryPreferences.prune(keeping: Set(categories.map(\.id)))
            historyRevision += 1
            return true
        } catch {
            recordCategoryError(error, fallback: .remove)
            return false
        }
    }

    /// Clears category field and command messages; saved data and task errors are unchanged.
    func clearCategoryIssues() {
        categoryNameIssue = nil
        categoryIssue = nil
        categoryReorderIssue = nil
    }

    /// Publish only the repository's committed catalog; task snapshots, drafts,
    /// collapse preferences and the task movement reveal are untouched.
    @discardableResult
    func moveCategory(_ request: CategoryMoveRequest, in context: CategoryReorderContext) -> CategoryMoveOutcome? {
        let presentation = taskWindowPresentation
        presentation.validateCategoryMovement(state: self)
        let authorized = presentation.categoryDragSession.authorizesSave(request, context: context)
        presentation.cancelCategoryMovement()
        guard authorized, presentation.canReorderCategories(in: context, state: self), let repository else { return nil }
        if case let .rejected(reason) = CategoryMovePlanner.plan(request, categories: categories) {
            categoryReorderIssue = .reorder
            return .rejected(reason)
        }
        do {
            let outcome = try repository.moveCategory(request)
            switch outcome {
            case let .changed(saved):
                categories = saved
                historyRevision += 1
                presentation.requestCategoryMovementReveal(categoryID: request.categoryID, context: context, catalog: saved)
                categoryReorderIssue = nil
            case .unchanged:
                categoryReorderIssue = nil
            case .rejected:
                categoryReorderIssue = .reorder
            }
            return outcome
        } catch {
            categoryReorderIssue = .reorder
            return nil
        }
    }

    func clearLaterIssues() {
        laterTaskIssue = nil
    }

    private func validatedCategoryName(_ name: String) -> String? {
        do {
            let validated = try TaskCategoryName.validate(name)
            categoryNameIssue = nil
            return validated
        } catch let error as TaskCategoryNameError {
            categoryNameIssue = .invalid(error)
            return nil
        } catch {
            return nil
        }
    }

    private func recordCategoryError(_ error: Error, fallback: CategoryCommandIssue) {
        switch error {
        case let nameError as TaskCategoryNameError:
            categoryNameIssue = .invalid(nameError)
        case TaskCategoryRepositoryError.duplicateName:
            categoryNameIssue = .duplicate
        case TaskCategoryRepositoryError.notFound:
            categoryIssue = .notFound
        case TaskCategoryRepositoryError.orderExhausted:
            categoryIssue = .orderExhausted
        default:
            categoryIssue = fallback
        }
    }

    /// Selects the category for a new task draft the user has just opened: the
    /// last-used category while it is still saved, otherwise General. A pending
    /// draft keeps its own selection, so callers skip this when one exists.
    func startNewDraft() {
        let lastUsed = categoryPreferences.lastUsedCategoryID
        draftCategoryID = isAvailable(lastUsed) ? lastUsed : nil
    }

    func cancelDraft() {
        draft = ""
        draftCategoryID = nil
        if taskIssue == .add { taskIssue = nil }
    }

    func startNewLaterDraft() {
        let lastUsed = categoryPreferences.laterLastUsedCategoryID
        laterDraftCategoryID = isAvailable(lastUsed) ? lastUsed : nil
    }

    func cancelLaterDraft() {
        laterDraft = ""
        laterDraftCategoryID = nil
        if laterTaskIssue == .add { laterTaskIssue = nil }
    }

    @discardableResult
    func addLaterDraft() -> Bool {
        let text = laterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryID = laterDraftCategoryID
        guard !text.isEmpty, readyForLaterWrite(), let repository else { return false }
        guard isAvailable(categoryID) else {
            reconcileLaterSelections(available: Set(categories.map(\.id)))
            return false
        }
        let task = LaterTask(id: UUID(), text: text, createdAt: day.now(),
                             completedAt: nil, categoryID: categoryID)
        do {
            try repository.addLater(task)
            laterTasks.append(task)
            categoryPreferences.rememberLastUsed(categoryID, in: .later)
            categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: categoryID), in: .later)
            laterDraft = ""
            laterDraftCategoryID = nil
            laterTaskIssue = nil
            return true
        } catch {
            recordLaterError(error, fallback: .add)
            return false
        }
    }

    @discardableResult
    func setLaterCompleted(id: UUID, completed: Bool) -> Bool {
        guard readyForLaterWrite(), let repository,
              let index = laterTasks.firstIndex(where: { $0.id == id }) else { return false }
        let saved = laterTasks[index]
        let completedAt = completed ? day.now() : nil
        do {
            try repository.setLaterCompleted(id: id, completedAt: completedAt)
            laterTasks[index] = LaterTask(id: saved.id, text: saved.text, createdAt: saved.createdAt,
                                          completedAt: completedAt, categoryID: saved.categoryID)
            laterTaskIssue = nil
            return true
        } catch {
            recordLaterError(error, fallback: .complete)
            return false
        }
    }

    @discardableResult
    func saveLaterEdit() -> Bool {
        let text = laterEditDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = editingLaterTaskID,
              readyForLaterWrite(), let repository, editingLaterTaskID == id,
              let index = laterTasks.firstIndex(where: { $0.id == id }) else { return false }
        let categoryID = laterEditCategoryID
        guard isAvailable(categoryID) else {
            reconcileLaterSelections(available: Set(categories.map(\.id)))
            return false
        }
        let saved = laterTasks[index]
        do {
            try repository.updateLater(id: id, text: text, categoryID: categoryID)
            laterTasks[index] = LaterTask(id: saved.id, text: text, createdAt: saved.createdAt,
                                          completedAt: saved.completedAt, categoryID: categoryID)
            if categoryID != saved.categoryID {
                categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: categoryID), in: .later)
            }
            cancelEditingLater()
            laterTaskIssue = nil
            return true
        } catch {
            recordLaterError(error, fallback: .edit)
            return false
        }
    }

    @discardableResult
    func deleteLater(id: UUID) -> Bool {
        guard readyForLaterWrite(), let repository,
              laterTasks.contains(where: { $0.id == id }) else { return false }
        do {
            try repository.deleteLater(id: id)
            laterTasks.removeAll { $0.id == id }
            if editingLaterTaskID == id { cancelEditingLater() }
            laterTaskIssue = nil
            return true
        } catch {
            recordLaterError(error, fallback: .delete)
            return false
        }
    }

    /// Transfer is one committed outcome. Never reread after success: a later
    /// read failure cannot turn a saved move into a failed, retryable write.
    @discardableResult
    func moveLaterToToday(id: UUID) -> Bool {
        let keys = day.keys()
        if todayKey != keys.today || !hasLoadedToday || !hasLoadedLater || !hasLoadedCatalog {
            refresh(keys: keys)
        }
        guard !isTerminating, hasLoadedCatalog, hasLoadedLater, hasLoadedToday,
              todayKey == keys.today, let repository,
              let source = laterTasks.first(where: { $0.id == id }),
              !source.isCompleted, isAvailable(source.categoryID) else { return false }
        do {
            let saved = try repository.moveLaterToToday(id: id, dayKey: keys.today)
            laterTasks.removeAll { $0.id == id }
            notes.append(saved)
            historyRevision += 1
            if editingLaterTaskID == id { cancelEditingLater() }
            categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: saved.categoryID), in: .today)
            laterTaskIssue = nil
            laterRefreshNotice = "Moved task to Today."
            return true
        } catch {
            recordLaterError(error, fallback: .moveToToday)
            return false
        }
    }

    /// A History selection is tied to the displayed day and action-time Today.
    /// Publish only the committed outcome, without a fallible post-write read.
    @discardableResult
    func continueHistoryTasks(_ sources: [Note], expectedToday: GregorianDay) -> Bool {
        let instant = day.now()
        let keys = day.keys(for: instant)
        continuationMessage = nil
        continuationFailed = false
        guard keys.today == expectedToday.key else {
            refresh()
            continuationFailed = true
            continuationMessage = "The date changed. Review your selection and try again."
            return false
        }
        if todayKey != keys.today || !hasLoadedToday || !hasLoadedCatalog { refresh(keys: keys) }
        guard !isTerminating, hasLoadedToday, hasLoadedCatalog, let repository,
              taskWindowPresentation.route == .history || taskWindowPresentation.route == .unfinishedDay,
              taskWindowPresentation.canBrowse(state: self),
              let snapshot = taskWindowPresentation.historyState?.daySnapshot,
              !sources.isEmpty, sources.allSatisfy({ snapshot.notes.contains($0) && $0.isUnfinished && $0.dayKey < keys.today }) else {
            continuationFailed = true
            continuationMessage = "Could not continue tasks. Reload the day and try again."
            return false
        }
        do {
            let saved = try repository.continueTasks(sources, to: keys.today, at: instant)
            notes.append(contentsOf: saved)
            yesterdayIncompleteCount = max(0, yesterdayIncompleteCount - sources.count { $0.dayKey == keys.yesterday })
            for note in saved {
                categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: note.categoryID), in: .today)
            }
            historyRevision += 1
            continuationMessage = saved.count == 1 ? "Continued 1 task in Today." : "Continued \(saved.count) tasks in Today."
            taskWindowPresentation.refreshBrowser(state: self)
            return true
        } catch {
            if case TaskContinuationError.staleSource = error {
                historyRevision += 1
                taskWindowPresentation.refreshBrowser(state: self)
            }
            continuationFailed = true
            continuationMessage = "Could not continue tasks. Reload the day and try again."
            return false
        }
    }

    func clearContinuationMessage() {
        continuationMessage = nil
        continuationFailed = false
    }

    private func recordLaterError(_ error: Error, fallback: DailyNotesIssue) {
        switch error {
        case LaterTaskRepositoryError.notFound, LaterTaskRepositoryError.alreadyCompleted,
             TaskCategoryRepositoryError.notFound:
            // Only storage's explicit stale-target/category result justifies
            // recovery. An ordinary failed write leaves snapshots/drafts intact.
            refresh()
        default:
            break
        }
        laterTaskIssue = fallback
    }

    @discardableResult
    func addDraft() -> Bool {
        let categoryID = draftCategoryID
        switch add(text: draft, categoryID: categoryID) {
        case .added:
            // Only a saved new task from Today sets the last-used category.
            categoryPreferences.rememberLastUsed(categoryID)
            // Show the saved task, even in a group the user had collapsed.
            categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: categoryID))
            draft = ""
            draftCategoryID = nil
            taskIssue = nil
            return true
        case .writeFailed:
            taskIssue = .add
            return false
        case .unavailable:
            // A selection missing from the loaded catalog falls back visibly.
            if hasLoadedToday { reconcileSelections(available: Set(categories.map(\.id))) }
            return false
        case .empty:
            return false
        }
    }

    /// Saves a task for the current local day without reading or changing the
    /// window's draft or issue. A readiness refresh may still update shared state.
    /// A nil category is General, which the capture panel always uses.
    func add(text rawText: String, categoryID: UUID? = nil) -> AddOutcome {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        let instant = day.now()
        let key = day.key(for: instant)
        guard readyForWrite(on: key), let repository,
              isAvailable(categoryID) else { return .unavailable }
        let note = Note(id: UUID(), text: text, dayKey: key,
                        createdAt: instant, completedAt: nil, categoryID: categoryID)
        do {
            try repository.add(note)
            notes.append(note)
            historyRevision += 1
            return .added
        } catch {
            return .writeFailed
        }
    }

    /// A non-nil outcome is the common saved-move contract. Only `.changed`
    /// authorizes a caller to reveal the destination; nil is blocked or failed.
    @discardableResult
    func moveTask(_ request: TaskMoveRequest) -> TaskMoveOutcome? {
        taskWindowPresentation.cancelMovement()
        guard !isTerminating else {
            taskIssue = .move
            return nil
        }
        let key = day.keys().today
        // Refresh a rollover for normal recovery, but never retarget its payload.
        if todayKey != key { refresh() }
        guard request.expectedDayKey == key else {
            taskIssue = .move
            return .rejected(.dayChanged)
        }
        guard taskWindowPresentation.canMoveTask(state: self), let repository else {
            taskIssue = .move
            return nil
        }
        // Validate the displayed snapshot, then let storage revalidate its fresh
        // transactional snapshot. Never publish this planner's proposal.
        if case let .rejected(reason) = TaskMovePlanner.plan(
            request, dayKey: key, notes: notes, categories: categories
        ) {
            taskIssue = .move
            return .rejected(reason)
        }
        do {
            let outcome = try repository.moveTask(request)
            switch outcome {
            case let .changed(saved):
                notes = saved
                historyRevision += 1
                categoryPreferences.setCollapsed(false, for: request.destinationGroup)
                taskWindowPresentation.requestMovementReveal(request)
                taskIssue = nil
            case .unchanged:
                if taskIssue == .move { taskIssue = nil }
            case .rejected:
                taskIssue = .move
            }
            return outcome
        } catch {
            taskIssue = .move
            return nil
        }
    }

    @discardableResult
    func setCompleted(id: UUID, completed: Bool) -> Bool {
        let instant = day.now()
        guard readyForExistingTask(on: day.key(for: instant)), let repository,
              let index = notes.firstIndex(where: { $0.id == id }), notes[index].continuedOn == nil else { return false }
        let saved = notes[index]
        let completedAt = completed ? instant : nil
        do {
            try repository.setCompleted(id: id, completedAt: completedAt)
            notes[index] = Note(id: saved.id, text: saved.text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: completedAt,
                                categoryID: saved.categoryID)
            taskIssue = nil
            historyRevision += 1
            return true
        } catch {
            taskIssue = .complete
            return false
        }
    }

    func beginEditing(id: UUID) {
        guard readyForExistingTask(on: day.keys().today),
              let note = notes.first(where: { $0.id == id }), note.continuedOn == nil else { return }
        editingNoteID = id
        editDraft = note.text
        editCategoryID = note.categoryID
    }

    func cancelEditing() {
        editingNoteID = nil
        editDraft = ""
        editCategoryID = nil
        if taskIssue == .edit { taskIssue = nil }
    }

    func beginEditingLater(id: UUID) {
        guard readyForLaterWrite(),
              let task = laterTasks.first(where: { $0.id == id }) else { return }
        editingLaterTaskID = id
        laterEditDraft = task.text
        laterEditCategoryID = task.categoryID
    }

    func cancelEditingLater() {
        editingLaterTaskID = nil
        laterEditDraft = ""
        laterEditCategoryID = nil
        if laterTaskIssue == .edit { laterTaskIssue = nil }
    }

    /// Saves text and category in one write; a category-only change is an edit.
    @discardableResult
    func saveEdit() -> Bool {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A readiness refresh can cancel the edit while its task still exists.
        guard !text.isEmpty, let id = editingNoteID,
              readyForExistingTask(on: day.keys().today), let repository,
              editingNoteID == id,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let categoryID = editCategoryID
        guard isAvailable(categoryID) else {
            reconcileSelections(available: Set(categories.map(\.id)))
            return false
        }
        let saved = notes[index]
        do {
            try repository.update(id: id, text: text, categoryID: categoryID)
            notes[index] = Note(id: saved.id, text: text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: saved.completedAt,
                                categoryID: categoryID)
            // A reassigned task stays visible; a text-only edit changes no group.
            if categoryID != saved.categoryID {
                categoryPreferences.setCollapsed(false, for: TaskGroupID(categoryID: categoryID))
            }
            cancelEditing()
            taskIssue = nil
            historyRevision += 1
            return true
        } catch {
            taskIssue = .edit
            return false
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard readyForExistingTask(on: day.keys().today), let repository,
              notes.contains(where: { $0.id == id }) else { return false }
        do {
            try repository.delete(id: id)
            notes.removeAll { $0.id == id }
            if editingNoteID == id { cancelEditing() }
            taskIssue = nil
            historyRevision += 1
            return true
        } catch {
            taskIssue = .delete
            return false
        }
    }

    /// Call before replacing `categories`, so a removed category keeps its name.
    private func invalidateEditing() {
        if editingNoteID != nil {
            recoveredEdit = RecoveredEdit(
                text: editDraft, categoryID: editCategoryID,
                categoryName: editCategoryID.flatMap { id in categories.first { $0.id == id }?.name }
            )
        }
        cancelEditing()
    }

    private func invalidateEditingLater() {
        if editingLaterTaskID != nil {
            laterRecoveredEdit = RecoveredEdit(
                text: laterEditDraft, categoryID: laterEditCategoryID,
                categoryName: laterEditCategoryID.flatMap { id in categories.first { $0.id == id }?.name }
            )
        }
        cancelEditingLater()
    }

    /// Applies a published catalog to draft selections. A missing new-task
    /// category becomes General and keeps the text; a missing edit category
    /// cancels the edit for recovery rather than saving it as General. Renames
    /// keep the same ID and change nothing here.
    private func reconcileSelections(available ids: Set<UUID>) {
        let editLost = editingNoteID != nil && editCategoryID.map { !ids.contains($0) } == true
        let draftLost = draftCategoryID.map { !ids.contains($0) } == true
        if editLost { invalidateEditing() }
        if draftLost { draftCategoryID = nil }
        switch (draftLost, editLost) {
        case (true, true):
            refreshNotice = "A selected category is no longer available. The new task will use General, and unsaved edit text was kept for recovery."
        case (true, false):
            refreshNotice = "The selected category is no longer available. The new task will use General."
        case (false, true):
            refreshNotice = "The selected category is no longer available. Unsaved edit text was kept for recovery."
        case (false, false):
            break
        }
    }

    private func reconcileLaterSelections(available ids: Set<UUID>) {
        let editLost = editingLaterTaskID != nil && laterEditCategoryID.map { !ids.contains($0) } == true
        let draftLost = laterDraftCategoryID.map { !ids.contains($0) } == true
        if editLost { invalidateEditingLater() }
        if draftLost { laterDraftCategoryID = nil }
        switch (draftLost, editLost) {
        case (true, true):
            laterRefreshNotice = "A selected category is no longer available. The new task will use General, and unsaved edit text was kept for recovery."
        case (true, false):
            laterRefreshNotice = "The selected category is no longer available. The new task will use General."
        case (false, true):
            laterRefreshNotice = "The selected category is no longer available. Unsaved edit text was kept for recovery."
        case (false, false):
            break
        }
    }

    private func isAvailable(_ categoryID: UUID?) -> Bool {
        categoryID.map { id in categories.contains { $0.id == id } } ?? true
    }

    /// Existing-row actions belong to the displayed day. A rollover refresh
    /// cancels that action even if a repository were to return the same ID.
    private func readyForExistingTask(on key: String) -> Bool {
        guard todayKey == key else {
            refresh()
            return false
        }
        return readyForWrite(on: key)
    }

    private func readyForWrite(on key: String) -> Bool {
        guard !isTerminating else { return false }
        if todayKey != key || !hasLoadedToday { refresh() }
        return todayKey == key && hasLoadedToday
    }

    private func readyForLaterWrite() -> Bool {
        guard !isTerminating else { return false }
        if !hasLoadedCatalog || !hasLoadedLater { refresh() }
        return hasLoadedCatalog && hasLoadedLater
    }

    private func readyForCategoryWrite() -> Bool {
        guard !isTerminating else { return false }
        if !hasLoadedCatalog || (!hasLoadedToday && !hasLoadedLater) { refresh() }
        return hasLoadedCatalog && (hasLoadedToday || hasLoadedLater)
    }

    /// Read-only access to the shared connection. These calls intentionally skip
    /// Today readiness, refresh, and all draft/error publication.
    func daySummaries(in range: HistoryDayRange) throws -> [DayTaskSummary] {
        try openRepository().daySummaries(in: range)
    }

    func historyDaySnapshot(for dayKey: String) throws -> HistoryDaySnapshot {
        try openRepository().historyDaySnapshot(for: dayKey)
    }

    func unfinishedDayPage(before: GregorianDay, limit: Int) throws -> UnfinishedDayPage {
        try openRepository().unfinishedDayPage(before: before, limit: limit)
    }

    private func openRepository() throws -> any NoteRepository {
        guard !isTerminating else { throw HistoryReadError.terminated }
        if let repository { return repository }
        let opened = try repositoryFactory()
        repository = opened
        return opened
    }
}
