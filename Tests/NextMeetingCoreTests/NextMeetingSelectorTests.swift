import Foundation
import Testing
@testable import NextMeetingCore

struct NextMeetingSelectorTests {
    let now = Fixtures.now

    func select(_ meetings: [Meeting], now: Date? = nil) -> MeetingSelection {
        NextMeetingSelector.select(meetings, now: now ?? self.now, calendar: Fixtures.calendar)
    }

    @Test func picksEarliestFutureMeeting() {
        let a = Fixtures.meeting("A", start: Fixtures.date(hour: 11))
        let b = Fixtures.meeting("B", start: Fixtures.date(hour: 10, minute: 30))
        #expect(select([a, b]).next?.title == "B")
    }

    @Test func excludesAllDayCancelledAndDeclined() {
        let meetings = [
            Fixtures.meeting("All day", start: Fixtures.date(hour: 0), minutes: 24 * 60, allDay: true),
            Fixtures.meeting("Cancelled", start: Fixtures.date(hour: 10, minute: 15), cancelled: true),
            Fixtures.meeting("Declined", start: Fixtures.date(hour: 10, minute: 20), declined: true),
            Fixtures.meeting("Real", start: Fixtures.date(hour: 14)),
        ]
        let selection = select(meetings)
        #expect(selection.next?.title == "Real")
        #expect(selection.later.isEmpty)
    }

    @Test func meetingStartedWithinTenMinutesWins() {
        let started = Fixtures.meeting("Started", start: Fixtures.date(hour: 9, minute: 52))
        let soon = Fixtures.meeting("Soon", start: Fixtures.date(hour: 10, minute: 5))
        let selection = select([soon, started])
        #expect(selection.next?.title == "Started")
        #expect(selection.alsoJoinable.isEmpty)
        #expect(selection.later.map(\.title) == ["Soon"])
    }

    @Test func overlappingJustStartedMeetingsAreAllKept() {
        let first = Fixtures.meeting("First", start: Fixtures.date(hour: 9, minute: 52), notes: "https://zoom.us/j/111")
        let second = Fixtures.meeting("Second", start: Fixtures.date(hour: 9, minute: 58), notes: "https://meet.google.com/abc-defg-hij")
        let third = Fixtures.meeting("Third", start: Fixtures.date(hour: 9, minute: 55))
        let tooOld = Fixtures.meeting("Too old", start: Fixtures.date(hour: 9, minute: 45))
        let soon = Fixtures.meeting("Soon", start: Fixtures.date(hour: 10, minute: 5))
        let selection = select([soon, second, tooOld, first, third])
        #expect(selection.next?.title == "First")
        #expect(selection.alsoJoinable.map(\.title) == ["Third", "Second"])
        #expect(selection.alsoJoinable.last?.link?.provider == .googleMeet)
        #expect(selection.later.map(\.title) == ["Soon"])
    }

    @Test func alsoJoinableIsEmptyWhenNextIsUpcoming() {
        let inProgress = Fixtures.meeting("Long", start: Fixtures.date(hour: 9), minutes: 120)
        let soon = Fixtures.meeting("Soon", start: Fixtures.date(hour: 10, minute: 5))
        let selection = select([inProgress, soon])
        #expect(selection.next?.title == "Soon")
        #expect(selection.alsoJoinable.isEmpty)
    }

    @Test func tenMinuteBoundaryIsInclusive() {
        let started = Fixtures.meeting("Started", start: Fixtures.date(hour: 9, minute: 50))
        let soon = Fixtures.meeting("Soon", start: Fixtures.date(hour: 10, minute: 5))
        #expect(select([soon, started]).next?.title == "Started")
    }

    @Test func meetingStartedLongerAgoLosesToUpcoming() {
        let started = Fixtures.meeting("Started", start: Fixtures.date(hour: 9, minute: 30), minutes: 60)
        let soon = Fixtures.meeting("Soon", start: Fixtures.date(hour: 10, minute: 30))
        #expect(select([started, soon]).next?.title == "Soon")
    }

    @Test func fallsBackToMeetingInProgress() {
        let started = Fixtures.meeting("Workshop", start: Fixtures.date(hour: 9), minutes: 180)
        #expect(select([started]).next?.title == "Workshop")
    }

    @Test func ignoresFinishedMeetings() {
        let done = Fixtures.meeting("Done", start: Fixtures.date(hour: 9, minute: 55), minutes: 5)
        #expect(select([done]).next == nil)
        #expect(select([]) == .empty)
    }

    @Test func laterListIsOrderedAndLimitedToTomorrow() {
        let meetings = [
            Fixtures.meeting("Day after", start: Fixtures.date(day: 21, hour: 9)),
            Fixtures.meeting("Tomorrow 9", start: Fixtures.date(day: 20, hour: 9)),
            Fixtures.meeting("Today 15", start: Fixtures.date(hour: 15)),
            Fixtures.meeting("Next", start: Fixtures.date(hour: 10, minute: 30)),
            Fixtures.meeting("Today 13", start: Fixtures.date(hour: 13)),
            Fixtures.meeting("Tomorrow late", start: Fixtures.date(day: 20, hour: 23, minute: 30)),
        ]
        let selection = select(meetings)
        #expect(selection.next?.title == "Next")
        #expect(selection.later.map(\.title) == ["Today 13", "Today 15", "Tomorrow 9", "Tomorrow late"])
    }

    @Test func laterListIsCappedAtEight() {
        let meetings = (0..<12).map { i in
            Fixtures.meeting("M\(i)", start: Fixtures.date(hour: 11 + i / 2, minute: (i % 2) * 30))
        }
        let selection = select(meetings)
        #expect(selection.next?.title == "M0")
        #expect(selection.later.count == NextMeetingSelector.laterLimit)
        #expect(selection.later.map(\.title) == (1...8).map { "M\($0)" })
    }

    @Test func laterExcludesOtherInProgressMeetings() {
        let longRunning = Fixtures.meeting("Focus block", start: Fixtures.date(hour: 8), minutes: 240)
        let next = Fixtures.meeting("Next", start: Fixtures.date(hour: 10, minute: 30))
        let selection = select([longRunning, next])
        #expect(selection.next?.title == "Next")
        #expect(selection.later.isEmpty)
    }

    @Test func groupsByDay() {
        let meetings = [
            Fixtures.meeting("A", start: Fixtures.date(hour: 13)),
            Fixtures.meeting("B", start: Fixtures.date(hour: 15)),
            Fixtures.meeting("C", start: Fixtures.date(day: 20, hour: 9)),
        ]
        let groups = NextMeetingSelector.groupByDay(meetings, calendar: Fixtures.calendar)
        #expect(groups.map { $0.meetings.map(\.title) } == [["A", "B"], ["C"]])
        #expect(groups.map(\.day) == [Fixtures.date(hour: 0), Fixtures.date(day: 20, hour: 0)])
    }
}
