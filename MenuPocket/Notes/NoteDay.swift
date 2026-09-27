import Foundation

/// Produces Gregorian YYYY-MM-DD keys in the injected calendar's time zone.
/// One `keys()` call uses one clock reading, including at midnight.
struct NoteDay {
    let calendar: Calendar
    let now: () -> Date

    init(calendar: Calendar = Calendar(identifier: .gregorian), now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    func keys() -> (today: String, yesterday: String) {
        let instant = now()
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: instant) else {
            preconditionFailure("Could not determine the previous calendar day")
        }
        return (key(for: instant), key(for: previousDay))
    }

    func key(for instant: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Could not determine a calendar day")
        }
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                      year, month, day)
    }
}
