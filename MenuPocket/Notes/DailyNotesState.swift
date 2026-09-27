import Foundation
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

/// The panel's single source of saved daily data. Drafts remain local until a
/// repository write succeeds; a failed read never publishes a partial snapshot.
@MainActor
@Observable
final class DailyNotesState {
    private(set) var todayKey: String?
    private(set) var notes: [Note] = []
    private(set) var yesterdayIncompleteCount = 0
    private(set) var hasLoadedToday = false
    private(set) var issue: DailyNotesIssue?

    var draft = ""
    private(set) var editingNoteID: UUID?
    var editDraft = ""

    @ObservationIgnored private let repositoryFactory: () throws -> any NoteRepository
    @ObservationIgnored private var repository: (any NoteRepository)?
    @ObservationIgnored private let day: NoteDay
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored nonisolated(unsafe) private var dayChangeObserver: NSObjectProtocol?

    var progress: NoteProgress {
        NoteProgress(notes: notes, for: todayKey ?? "")
    }

    var errorMessage: String? { issue?.message }

    init(
        repositoryFactory: @escaping () throws -> any NoteRepository = { try SQLiteNoteRepository() },
        day: NoteDay = NoteDay(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.repositoryFactory = repositoryFactory
        self.day = day
        self.notificationCenter = notificationCenter
        dayChangeObserver = notificationCenter.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIfDayChanged() }
        }
    }

    deinit {
        if let dayChangeObserver {
            notificationCenter.removeObserver(dayChangeObserver)
        }
    }

    func panelDidOpen() {
        refresh()
    }

    func refreshIfDayChanged() {
        if day.keys().today != todayKey { refresh() }
    }

    func refresh() {
        let keys = day.keys()
        do {
            let store = try openRepository()
            let savedNotes = try store.notes(for: keys.today)
            let previousCount = try store.incompleteCount(for: keys.yesterday)
            todayKey = keys.today
            notes = NoteOrder.sorted(savedNotes.filter { $0.dayKey == keys.today })
            if let editingNoteID, !notes.contains(where: { $0.id == editingNoteID }) {
                cancelEditing()
            }
            yesterdayIncompleteCount = previousCount
            hasLoadedToday = true
            issue = nil
        } catch {
            // Do not label a previous day's cached notes as today's after midnight.
            if todayKey != keys.today {
                todayKey = keys.today
                notes = []
                cancelEditing()
                yesterdayIncompleteCount = 0
                hasLoadedToday = false
            }
            issue = .load
        }
    }

    @discardableResult
    func addDraft() -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let instant = day.now()
        let key = day.key(for: instant)
        guard readyForWrite(on: key), let repository else { return false }
        let note = Note(id: UUID(), text: text, dayKey: key,
                        createdAt: instant, completedAt: nil)
        do {
            try repository.add(note)
            notes = NoteOrder.sorted(notes + [note])
            draft = ""
            issue = nil
            return true
        } catch {
            issue = .add
            return false
        }
    }

    @discardableResult
    func setCompleted(id: UUID, completed: Bool) -> Bool {
        let instant = day.now()
        guard readyForWrite(on: day.key(for: instant)), let repository,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let saved = notes[index]
        let completedAt = completed ? instant : nil
        do {
            try repository.setCompleted(id: id, completedAt: completedAt)
            notes[index] = Note(id: saved.id, text: saved.text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: completedAt)
            notes = NoteOrder.sorted(notes)
            issue = nil
            return true
        } catch {
            issue = .complete
            return false
        }
    }

    func beginEditing(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        editingNoteID = id
        editDraft = note.text
    }

    func cancelEditing() {
        editingNoteID = nil
        editDraft = ""
    }

    @discardableResult
    func saveEdit() -> Bool {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = editingNoteID,
              readyForWrite(on: day.keys().today), let repository,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let saved = notes[index]
        do {
            try repository.updateText(id: id, text: text)
            notes[index] = Note(id: saved.id, text: text, dayKey: saved.dayKey,
                                createdAt: saved.createdAt, completedAt: saved.completedAt)
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
        guard readyForWrite(on: day.keys().today), let repository,
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
