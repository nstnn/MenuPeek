import AppKit
import Observation

enum DailyNotesIssue: Equatable {
    case load
    case add
    case complete
    case edit
    case delete

    var message: String {
        switch self {
        case .load: "Could not load notes. Try again."
        case .add: "Could not save note. Try again."
        case .complete: "Could not update note. Try again."
        case .edit: "Could not save edit. Try again."
        case .delete: "Could not delete note. Try again."
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
    case remove
    case usage
    case notFound
    case orderExhausted

    var message: String {
        switch self {
        case .create: "Could not create category. Try again."
        case .rename: "Could not rename category. Try again."
        case .remove: "Could not remove category. Try again."
        case .usage: "Could not count this category's tasks. Try again."
        case .notFound: "This category is no longer available."
        case .orderExhausted: "No more categories can be created."
        }
    }
}

/// The app's single source of saved daily data. Drafts remain local until a
/// repository write succeeds; a failed read never publishes a partial snapshot.
@MainActor
@Observable
final class DailyNotesState {
    enum AddOutcome: Equatable {
        case added
        case empty
        case unavailable
        case writeFailed
    }

    private(set) var todayKey: String?
    private(set) var categories: [TaskCategory] = []
    private(set) var notes: [Note] = []
    private(set) var yesterdayIncompleteCount = 0
    private(set) var hasLoadedToday = false
    private(set) var readIssue: DailyNotesIssue?
    private(set) var taskIssue: DailyNotesIssue?
    private(set) var categoryNameIssue: CategoryNameIssue?
    private(set) var categoryIssue: CategoryCommandIssue?

    /// Keep task-write errors through a failed read and its successful retry.
    /// Existing views still consume the load error first through this property.
    var issue: DailyNotesIssue? { readIssue ?? taskIssue }

    var draft = ""
    private(set) var editingNoteID: UUID?
    var editDraft = ""
    private(set) var recoveredEditDraft: String?
    private(set) var refreshNotice: String?

    /// nil means unloaded or the latest read failed; successful empty is 0/0.
    /// Write failures leave this last saved progress available.
    var availableProgress: NoteProgress? { hasLoadedToday ? progress : nil }
    var availableCategories: [TaskCategory]? { hasLoadedToday ? categories : nil }

    @ObservationIgnored private let repositoryFactory: () throws -> any NoteRepository
    @ObservationIgnored private var repository: (any NoteRepository)?
    @ObservationIgnored private let day: NoteDay
    @ObservationIgnored nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isTerminating = false

    var progress: NoteProgress {
        NoteProgress(notes: notes, for: todayKey ?? "")
    }

    var errorMessage: String? { issue?.message }

    init(
        repositoryFactory: @escaping () throws -> any NoteRepository = { try SQLiteNoteRepository() },
        day: NoteDay = NoteDay(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.repositoryFactory = repositoryFactory
        self.day = day
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

    // App lifecycle consumers can refresh without creating a view.
    func startup() { refresh() }
    func windowWillOpen() { refresh() }

    func stopForTermination() {
        isTerminating = true
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        repository = nil
    }

    func refreshIfDayChanged() {
        if day.keys().today != todayKey { refresh() }
    }

    func refresh() {
        guard !isTerminating else { return }
        let keys = day.keys()
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
        do {
            let store = try openRepository()
            let savedCategories = try store.categories()
            let savedNotes = try store.notes(for: keys.today)
            let previousCount = try store.incompleteCount(for: keys.yesterday)
            let categoryIDs = Set(savedCategories.map(\.id))
            guard savedNotes.allSatisfy({ note in
                note.categoryID.map { categoryIDs.contains($0) } ?? true
            }) else { throw TaskCategoryRepositoryError.invalidRow }
            todayKey = keys.today
            categories = savedCategories
            notes = savedNotes.filter { $0.dayKey == keys.today }
            if let editingNoteID, !notes.contains(where: { $0.id == editingNoteID }) {
                invalidateEditing()
                refreshNotice = "The edited task is no longer available. Unsaved text was kept for recovery."
            }
            yesterdayIncompleteCount = previousCount
            hasLoadedToday = true
            readIssue = nil
        } catch {
            hasLoadedToday = false
            readIssue = .load
        }
    }

    @discardableResult
    func createCategory(name: String) -> TaskCategory? {
        categoryIssue = nil
        guard let name = validatedCategoryName(name),
              readyForWrite(on: day.keys().today), let repository else { return nil }
        do {
            let saved = try repository.createCategory(name: name)
            categories.append(saved)
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
              readyForWrite(on: day.keys().today), let repository else { return nil }
        guard let index = categories.firstIndex(where: { $0.id == id }) else {
            categoryIssue = .notFound
            return nil
        }
        do {
            let saved = try repository.renameCategory(id: id, name: name)
            categories[index] = saved
            return saved
        } catch {
            recordCategoryError(error, fallback: .rename)
            return nil
        }
    }

    /// Counts completed and incomplete assignments across every saved day.
    /// A failed usage read does not invalidate the already loaded daily snapshot.
    func categoryUsageCount(id: UUID) -> Int? {
        categoryIssue = nil
        guard readyForWrite(on: day.keys().today), let repository else { return nil }
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
        guard readyForWrite(on: day.keys().today), let repository else { return false }
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
                            categoryID: nil)
            }
            categories.removeAll { $0.id == id }
            return true
        } catch {
            recordCategoryError(error, fallback: .remove)
            return false
        }
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

    func cancelDraft() {
        draft = ""
        if taskIssue == .add { taskIssue = nil }
    }

    @discardableResult
    func addDraft() -> Bool {
        switch add(text: draft) {
        case .added:
            draft = ""
            taskIssue = nil
            return true
        case .writeFailed:
            taskIssue = .add
            return false
        case .empty, .unavailable:
            return false
        }
    }

    /// Saves a task for the current local day without reading or changing the
    /// window's draft or issue. A readiness refresh may still update shared state.
    func add(text rawText: String) -> AddOutcome {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        let instant = day.now()
        let key = day.key(for: instant)
        guard readyForWrite(on: key), let repository else { return .unavailable }
        let note = Note(id: UUID(), text: text, dayKey: key,
                        createdAt: instant, completedAt: nil)
        do {
            try repository.add(note)
            notes.append(note)
            return .added
        } catch {
            return .writeFailed
        }
    }

    @discardableResult
    func setCompleted(id: UUID, completed: Bool) -> Bool {
        let instant = day.now()
        guard readyForExistingTask(on: day.key(for: instant)), let repository,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let saved = notes[index]
        let completedAt = completed ? instant : nil
        do {
            try repository.setCompleted(id: id, completedAt: completedAt)
            notes[index] = Note(id: saved.id, text: saved.text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: completedAt,
                                categoryID: saved.categoryID)
            taskIssue = nil
            return true
        } catch {
            taskIssue = .complete
            return false
        }
    }

    func beginEditing(id: UUID) {
        guard readyForExistingTask(on: day.keys().today),
              let note = notes.first(where: { $0.id == id }) else { return }
        editingNoteID = id
        editDraft = note.text
    }

    func cancelEditing() {
        editingNoteID = nil
        editDraft = ""
        if taskIssue == .edit { taskIssue = nil }
    }

    @discardableResult
    func saveEdit() -> Bool {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = editingNoteID,
              readyForExistingTask(on: day.keys().today), let repository,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let saved = notes[index]
        do {
            try repository.update(id: id, text: text, categoryID: saved.categoryID)
            notes[index] = Note(id: saved.id, text: text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: saved.completedAt,
                                categoryID: saved.categoryID)
            cancelEditing()
            taskIssue = nil
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
            return true
        } catch {
            taskIssue = .delete
            return false
        }
    }

    private func invalidateEditing() {
        if editingNoteID != nil { recoveredEditDraft = editDraft }
        cancelEditing()
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
        if todayKey != key || !hasLoadedToday { refresh() }
        return todayKey == key && hasLoadedToday
    }

    private func openRepository() throws -> any NoteRepository {
        if let repository { return repository }
        let opened = try repositoryFactory()
        repository = opened
        return opened
    }
}
