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
    private(set) var notes: [Note] = []
    private(set) var yesterdayIncompleteCount = 0
    private(set) var hasLoadedToday = false
    private(set) var issue: DailyNotesIssue?

    var draft = ""
    private(set) var editingNoteID: UUID?
    var editDraft = ""
    private(set) var recoveredEditDraft: String?
    private(set) var refreshNotice: String?

    /// nil means unloaded or the latest read failed; successful empty is 0/0.
    /// Write failures leave this last saved progress available.
    var availableProgress: NoteProgress? { hasLoadedToday ? progress : nil }

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
            if hadPreviousDay {
                refreshNotice = "The date changed. Previous task actions were cancelled; unsaved text is still available."
            }
        }
        do {
            let store = try openRepository()
            let savedNotes = try store.notes(for: keys.today)
            let previousCount = try store.incompleteCount(for: keys.yesterday)
            todayKey = keys.today
            notes = savedNotes.filter { $0.dayKey == keys.today }
            if let editingNoteID, !notes.contains(where: { $0.id == editingNoteID }) {
                invalidateEditing()
                refreshNotice = "The edited task is no longer available. Unsaved text was kept for recovery."
            }
            yesterdayIncompleteCount = previousCount
            hasLoadedToday = true
            issue = nil
        } catch {
            hasLoadedToday = false
            issue = .load
        }
    }

    func cancelDraft() {
        draft = ""
        if issue == .add { issue = nil }
    }

    @discardableResult
    func addDraft() -> Bool {
        switch add(text: draft) {
        case .added:
            draft = ""
            issue = nil
            return true
        case .writeFailed:
            issue = .add
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
            issue = nil
            return true
        } catch {
            issue = .complete
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
        if issue == .edit { issue = nil }
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
            issue = nil
            return true
        } catch {
            issue = .edit
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
            issue = nil
            return true
        } catch {
            issue = .delete
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
