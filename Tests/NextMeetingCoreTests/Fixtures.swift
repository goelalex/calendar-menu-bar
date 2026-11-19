import Foundation
@testable import NextMeetingCore

enum Fixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    static let locale = Locale(identifier: "en_US_POSIX")

    /// Thursday 19 Nov 2026, 10:00 New York time.
    static let now = date(day: 19, hour: 10)

    static func date(day: Int = 19, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func meeting(
        _ title: String,
        start: Date,
        minutes: Int = 30,
        allDay: Bool = false,
        cancelled: Bool = false,
        declined: Bool = false,
        url: URL? = nil,
        location: String? = nil,
        notes: String? = nil
    ) -> Meeting {
        Meeting(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay,
            isCancelled: cancelled,
            isDeclined: declined,
            calendarID: "work",
            calendarTitle: "Work",
            url: url,
            location: location,
            notes: notes
        )
    }
}

extension String {
    /// ICU uses U+202F (narrow no-break space) before AM/PM; tests compare against plain spaces.
    var normalizedSpaces: String {
        replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
    }
}
