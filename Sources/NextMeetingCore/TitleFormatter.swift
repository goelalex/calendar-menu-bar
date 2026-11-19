import Foundation

/// Produces every user-visible string about a meeting. Locale/calendar are injectable for tests;
/// the app uses the autoupdating current ones so 12/24-hour and time zone changes apply live.
public struct TitleFormatter: Sendable {
    public var calendar: Calendar
    public var locale: Locale
    public var statusTitleLength = 25
    public var menuTitleLength = 60

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// Menu bar text: `Standup · in 12m`, `Standup · 2:30 PM`, `Standup · Tue 9:00 AM`, `Standup · now`.
    public func statusTitle(for meeting: Meeting, now: Date) -> String {
        "\(Self.truncate(meeting.displayTitle, to: statusTitleLength)) · \(relativeStart(of: meeting, now: now))"
    }

    public func relativeStart(of meeting: Meeting, now: Date) -> String {
        if meeting.start <= now { return "now" }
        let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        if calendar.isDate(meeting.start, inSameDayAs: now) { return time(meeting.start) }
        return format(meeting.start, template: "EEEjmm")
    }

    /// Title row of the dropdown.
    public func menuTitle(for meeting: Meeting) -> String {
        Self.truncate(meeting.displayTitle, to: menuTitleLength)
    }

    /// `Today, 2:30 – 3:00 PM`
    public func timeRange(for meeting: Meeting, now: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let sameDay = calendar.isDate(meeting.start, inSameDayAs: meeting.end)
        if !sameDay { formatter.dateStyle = .medium }
        let range = formatter.string(from: meeting.start, to: max(meeting.start, meeting.end))
        return sameDay ? "\(dayName(for: meeting.start, now: now)), \(range)" : range
    }

    /// Row in the "Later" list: `2:30 PM  Design review`.
    public func laterRow(for meeting: Meeting) -> String {
        "\(time(meeting.start))  \(Self.truncate(meeting.displayTitle, to: 45))"
    }

    /// `Today`, `Tomorrow`, `Yesterday`, else the weekday (`Tuesday`) within a week, else a date.
    public func dayName(for date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return format(date, template: "EEEE")
        default: return format(date, template: "EEEMMMd")
        }
    }

    public func time(_ date: Date) -> String {
        format(date, template: "jmm")
    }

    private func format(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func truncate(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        return text.prefix(length - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
