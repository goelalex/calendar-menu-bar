import Foundation
import Testing
@testable import NextMeetingCore

struct TitleFormatterTests {
    let formatter = TitleFormatter(calendar: Fixtures.calendar, locale: Fixtures.locale)
    let now = Fixtures.now

    func status(_ start: Date, title: String = "Standup") -> String {
        formatter.statusTitle(for: Fixtures.meeting(title, start: start), now: now).normalizedSpaces
    }

    @Test func minutesWhenUnderAnHour() {
        #expect(status(Fixtures.date(hour: 10, minute: 12)) == "Standup · in 12m")
        #expect(status(now.addingTimeInterval(30)) == "Standup · in 1m")
        #expect(status(Fixtures.date(hour: 10, minute: 59)) == "Standup · in 59m")
    }

    @Test func timeWhenLaterToday() {
        #expect(status(Fixtures.date(hour: 14, minute: 30)) == "Standup · 2:30 PM")
        #expect(status(Fixtures.date(hour: 11)) == "Standup · 11:00 AM")
    }

    @Test func weekdayWhenNotToday() {
        #expect(status(Fixtures.date(day: 24, hour: 9)) == "Standup · Tue 9:00 AM")
        #expect(status(Fixtures.date(day: 20, hour: 9)) == "Standup · Fri 9:00 AM")
    }

    @Test func nowWhenStarted() {
        #expect(status(Fixtures.date(hour: 9, minute: 55)) == "Standup · now")
        #expect(status(now) == "Standup · now")
    }

    @Test func truncatesLongTitles() {
        let title = status(Fixtures.date(hour: 10, minute: 12), title: "Quarterly planning review with the whole team")
        #expect(title == "Quarterly planning revie… · in 12m")
        #expect(title.split(separator: " · ")[0].count == 25)
    }

    @Test func fallsBackForEmptyTitle() {
        #expect(status(Fixtures.date(hour: 10, minute: 12), title: "  ") == "(No title) · in 12m")
    }

    @Test func laterRow() {
        let meeting = Fixtures.meeting("Design review", start: Fixtures.date(hour: 14, minute: 30))
        #expect(formatter.laterRow(for: meeting).normalizedSpaces == "2:30 PM  Design review")
    }

    @Test func dayNames() {
        #expect(formatter.dayName(for: Fixtures.date(hour: 0), now: now) == "Today")
        #expect(formatter.dayName(for: Fixtures.date(day: 20, hour: 0), now: now) == "Tomorrow")
        #expect(formatter.dayName(for: Fixtures.date(day: 23, hour: 0), now: now) == "Monday")
    }

    @Test func timeRange() {
        let meeting = Fixtures.meeting("Design review", start: Fixtures.date(hour: 14, minute: 30))
        let range = formatter.timeRange(for: meeting, now: now).normalizedSpaces
        #expect(range.hasPrefix("Today, 2:30"))
        #expect(range.hasSuffix("3:00 PM"))
    }

    @Test func respects24HourLocale() {
        let german = TitleFormatter(calendar: Fixtures.calendar, locale: Locale(identifier: "de_DE"))
        let meeting = Fixtures.meeting("Standup", start: Fixtures.date(hour: 14, minute: 30))
        #expect(german.statusTitle(for: meeting, now: now) == "Standup · 14:30")
    }
}
