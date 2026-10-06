import Foundation

/// Produces Gregorian YYYY-MM-DD keys in the injected calendar's time zone.
/// One `keys()` call uses one clock reading, including at midnight.
struct NoteDay {
    private let calendarProvider: () -> Calendar
    var calendar: Calendar { calendarProvider() }
    let now: () -> Date

    init(calendar: Calendar, now: @escaping () -> Date = Date.init) {
        self.calendarProvider = { calendar }
        self.now = now
    }

    /// The production calendar is rebuilt for each calculation so time-zone
    /// changes affect Today without rewriting stored creation-day keys.
    init(now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current }) {
        self.calendarProvider = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone()
            return calendar
        }
        self.now = now
    }

    func keys() -> (today: String, yesterday: String) {
        keys(for: now())
    }

    /// Reuses an action's clock sample and one calendar for both day keys.
    func keys(for instant: Date) -> (today: String, yesterday: String) {
        let calendar = calendar
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: instant) else {
            preconditionFailure("Could not determine the previous calendar day")
        }
        return (key(for: instant, calendar: calendar), key(for: previousDay, calendar: calendar))
    }

    func key(for instant: Date) -> String {
        key(for: instant, calendar: calendar)
    }

    private func key(for instant: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Could not determine a calendar day")
        }
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                      year, month, day)
    }
}
