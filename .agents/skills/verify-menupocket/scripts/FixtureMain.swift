import AppKit
import Foundation

// verify-menupocket fixture entry point. It replaces MenuPocketApp.swift and
// runs the production AppDelegate, state, windows, status item, glance, and
// Quick Add panel against isolated storage:
//   --data DIR             fixture.sqlite, day-offset, and the fail-open flag live here
//   --defaults-suite NAME  every preference, category choice, and onboarding marker
//   --seed empty|basic|category-reordering|calendar (only on a new database)
//   --now ISO8601          optional fixed instant (default: the real clock)
//   --tz IDENTIFIER        optional time zone (default: the Mac's)
// System boundaries are faked: login items always report disabled, and the
// Quick Add hotkey is never registered with Carbon. SIGUSR1 presses the fake
// hotkey; SIGUSR2 advances the clock one day and posts a day change.
// The `fail-open` file in --data makes opening storage throw (Unavailable).

private struct Options {
    var data: URL?
    var suite: String?
    var seed = "empty"
    var now: Date?
    var timeZone = TimeZone.current

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            let value = iterator.next() ?? ""
            switch flag {
            case "--data": data = URL(fileURLWithPath: value, isDirectory: true)
            case "--defaults-suite": suite = value
            case "--seed": seed = value
            case "--now": now = ISO8601DateFormatter().date(from: value)
            case "--tz": timeZone = TimeZone(identifier: value) ?? .current
            default: FileHandle.standardError.write(Data("fixture: ignoring \(flag)\n".utf8))
            }
        }
    }
}

private struct FixtureLogin: LoginItemService {
    func readStatus() -> LoginItemStatus { .disabled }
    func register() -> LoginItemOperationResult { .init(status: .disabled, failure: .registrationFailed) }
    func unregister() -> LoginItemOperationResult { .init(status: .disabled, failure: nil) }
    func openSystemSettingsLoginItems() {}
}

@MainActor private final class FixtureHotKey: HotKeyService {
    private(set) var onPress: (@MainActor () -> Void)?
    func register(_ combination: HotKeyCombination, onPress: @escaping @MainActor () -> Void) throws(HotKeyRegistrationError) {
        self.onPress = onPress
        log("hotkey registered (fake)")
    }
    func unregister() {
        onPress = nil
        log("hotkey unregistered (fake)")
    }
}

private struct FixtureOpenFailure: Error {}

private func log(_ message: String) {
    print("fixture: \(message)")
    fflush(stdout)
}

private func seedBasic(_ repository: SQLiteNoteRepository, day: NoteDay) throws {
    let now = day.now()
    let keys = day.keys()
    let calendar = day.calendar
    func key(daysAgo: Int) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    let work = try repository.createCategory(name: "Work")
    let errands = try repository.createCategory(name: "Errands")
    func add(_ dayKey: String, _ text: String, done: Bool = false, _ category: TaskCategory? = nil) throws {
        try repository.add(Note(id: UUID(), text: text, dayKey: dayKey, createdAt: now,
                                completedAt: done ? now : nil, categoryID: category?.id))
    }
    try add(keys.today, "Review pull request", work)
    try add(keys.today, "Write release notes", done: true, work)
    try add(keys.today, "Buy coffee beans", errands)
    try add(keys.today, "Water the plants")
    try add(keys.yesterday, "Call the dentist")
    try add(keys.yesterday, "Send weekly report", done: true, work)
    try add(key(daysAgo: 3), "Renew library books", errands)
    try repository.addLater(LaterTask(id: UUID(), text: "Plan the team offsite", createdAt: now, completedAt: nil, categoryID: work.id))
    try repository.addLater(LaterTask(id: UUID(), text: "Read the SQLite docs", createdAt: now, completedAt: nil))
}

private func seedCategoryReordering(_ repository: SQLiteNoteRepository, day: NoteDay) throws {
    try seedBasic(repository, day: day)
    _ = try repository.createCategory(name: "Unused")
    let learning = try repository.createCategory(name: "Learning and personal development with a long category name")
    let now = day.now()
    for index in 1...24 {
        try repository.add(Note(id: UUID(), text: "Practice exercise \(index)", dayKey: day.keys().today,
                                createdAt: now, completedAt: index == 1 ? now : nil, categoryID: learning.id))
    }
    let errands = try repository.categories().first { $0.name == "Errands" }!
    for category in [errands, learning] {
        try repository.addLater(LaterTask(id: UUID(), text: "Future practice: \(category.name)",
                                         createdAt: now, completedAt: nil, categoryID: category.id))
        try repository.add(Note(id: UUID(), text: "Previous practice: \(category.name)",
                                dayKey: day.keys().yesterday, createdAt: now,
                                completedAt: nil, categoryID: category.id))
    }
}

/// `basic` plus Calendar blocks in the week (Monday first) that contains the
/// fixture's today, so the seeded week is always the one Calendar opens on.
/// Covers a 15-minute block, a two-way and a three-way overlap, back-to-back
/// blocks, a long title, and a block that ends at 24:00.
private func seedCalendar(_ repository: SQLiteNoteRepository, day: NoteDay) throws {
    try seedBasic(repository, day: day)
    let today = try GregorianDay(key: day.keys().today)
    let monday = try today.adding(days: -today.weekdayOffset(from: ScheduleCalendar.firstWeekday))
    let now = day.now()
    var created = 0
    func add(_ title: String, _ weekday: Int, _ start: String, _ end: String) throws {
        func minute(_ text: String) -> Int {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            return parts[0] * 60 + parts[1]
        }
        created += 1
        try repository.addScheduleBlock(ScheduleBlock(
            id: UUID(), title: title, day: monday.adding(days: weekday),
            startMinute: minute(start), endMinute: minute(end),
            createdAt: now.addingTimeInterval(TimeInterval(created))))
    }
    try add("Standup", 0, "09:00", "09:15")
    try add("Deep work", 0, "09:30", "12:00")
    try add("Design review", today.weekdayOffset(from: ScheduleCalendar.firstWeekday), "10:00", "11:00")
    try add("Pairing", today.weekdayOffset(from: ScheduleCalendar.firstWeekday), "10:30", "11:30")
    try add("Lunch", today.weekdayOffset(from: ScheduleCalendar.firstWeekday), "12:00", "13:00")
    try add("Focus", today.weekdayOffset(from: ScheduleCalendar.firstWeekday), "13:00", "14:30")
    try add("Interviews", 3, "14:00", "16:00")
    try add("Sync", 3, "14:30", "15:30")
    try add("Retro", 3, "15:00", "16:00")
    try add("Quarterly planning with the whole product team", 4, "13:00", "15:00")
    try add("Wind down", 6, "23:45", "24:00")
}

@main struct FixtureMain {
    @MainActor static func main() throws {
        let options = Options(arguments: CommandLine.arguments)
        guard let data = options.data, let suite = options.suite,
              let defaults = UserDefaults(suiteName: suite) else {
            FileHandle.standardError.write(Data("fixture: --data and --defaults-suite are required\n".utf8))
            exit(64)
        }
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let database = data.appendingPathComponent("fixture.sqlite")
        let offsetFile = data.appendingPathComponent("day-offset")
        let failOpen = data.appendingPathComponent("fail-open")

        func dayOffset() -> Int {
            (try? String(contentsOf: offsetFile, encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        }
        let base = options.now
        let timeZone = options.timeZone
        let day = NoteDay(now: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.date(byAdding: .day, value: dayOffset(), to: base ?? Date())!
        }, timeZone: { timeZone })

        let isNew = !FileManager.default.fileExists(atPath: database.path)
        do {
            // Opening runs the production migrations on a new or older store.
            let repository = try SQLiteNoteRepository(databaseURL: database)
            if isNew, options.seed == "basic" { try seedBasic(repository, day: day) }
            if isNew, options.seed == "category-reordering" { try seedCategoryReordering(repository, day: day) }
            if isNew, options.seed == "calendar" { try seedCalendar(repository, day: day) }
        }
        log("database \(database.path) new=\(isNew) seed=\(isNew ? options.seed : "kept") today=\(day.keys().today)")

        let dayChanges = NotificationCenter()
        let state = DailyNotesState(
            repositoryFactory: {
                if FileManager.default.fileExists(atPath: failOpen.path) {
                    log("open storage refused (fail-open flag)")
                    throw FixtureOpenFailure()
                }
                return try SQLiteNoteRepository(databaseURL: database)
            },
            day: day,
            notificationCenter: dayChanges,
            workspaceNotificationCenter: NotificationCenter(),
            categoryPreferences: TaskCategoryPreferences(userDefaults: defaults)
        )
        let hotKey = FixtureHotKey()
        let model = AppModel(store: PreferencesStore(userDefaults: defaults),
                             loginItemService: FixtureLogin(), hotKeyService: hotKey)
        let delegate = AppDelegate(model: model, dailyNotesState: state,
                                   taskWindowZoom: TaskWindowZoom(userDefaults: defaults),
                                   onboardingStore: UserDefaultsOnboardingStore(userDefaults: defaults),
                                   launchContext: { .manual })

        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        let pressHotKey = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        pressHotKey.setEventHandler {
            MainActor.assumeIsolated {
                guard let onPress = hotKey.onPress else { return log("hotkey press ignored: Quick Add is off") }
                log("hotkey pressed (fake)")
                onPress()
            }
        }
        let nextDay = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        nextDay.setEventHandler {
            try? "\(dayOffset() + 1)".write(to: offsetFile, atomically: true, encoding: .utf8)
            log("day advanced: today=\(day.keys().today)")
            dayChanges.post(name: .NSCalendarDayChanged, object: nil)
        }
        pressHotKey.resume()
        nextDay.resume()

        let application = NSApplication.shared
        application.delegate = delegate
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)".write(to: data.appendingPathComponent("launched.pid"), atomically: true, encoding: .utf8)
        log("launched pid=\(pid)")
        application.run()
        withExtendedLifetime((delegate, pressHotKey, nextDay)) {}
    }
}
