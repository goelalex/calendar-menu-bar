import Foundation

public struct MeetingSelection: Sendable, Equatable {
    /// The meeting shown in the menu bar.
    public var next: Meeting?
    /// Other meetings that also started within the join grace period, by start time.
    /// Shown alongside `next` (each with its join link) so overlapping meetings aren't lost.
    public var alsoJoinable: [Meeting]
    public var later: [Meeting]

    public init(next: Meeting?, alsoJoinable: [Meeting] = [], later: [Meeting]) {
        self.next = next
        self.alsoJoinable = alsoJoinable
        self.later = later
    }

    public static let empty = MeetingSelection(next: nil, later: [])
}

/// Meetings that start on the same calendar day.
public struct DayGroup: Sendable, Equatable {
    public var day: Date
    public var meetings: [Meeting]
}

public enum NextMeetingSelector {
    /// How long after its start a meeting still counts as "next" (you can still join it).
    public static let joinGracePeriod: TimeInterval = 10 * 60
    public static let laterLimit = 8

    /// Picks the meeting for the menu bar and the "Later" list.
    ///
    /// Ignores all-day, cancelled, declined and already-finished events. The next meeting is,
    /// in order of preference: the earliest one that started within the last 10 minutes; the
    /// earliest future one; the in-progress one that started most recently. Any other meetings
    /// that started within the last 10 minutes go in `alsoJoinable`. "Later" holds the future
    /// meetings after `next` through the end of tomorrow, capped at `laterLimit`.
    public static func select(
        _ meetings: [Meeting],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> MeetingSelection {
        let candidates = meetings
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && $0.end > now }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }

        let justStarted = candidates.filter { $0.start <= now && now.timeIntervalSince($0.start) <= joinGracePeriod }
        let upcoming = candidates.first { $0.start > now }
        let inProgress = candidates.last { $0.start <= now }

        guard let next = justStarted.first ?? upcoming ?? inProgress else { return .empty }
        let alsoJoinable = justStarted.filter { $0.id != next.id }

        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? .distantFuture
        let later = candidates
            .filter { $0.id != next.id && $0.start >= next.start && $0.start > now && $0.start < endOfTomorrow }
            .prefix(laterLimit)

        return MeetingSelection(next: next, alsoJoinable: alsoJoinable, later: Array(later))
    }

    /// Groups meetings (already sorted by start) by the day they start on.
    public static func groupByDay(_ meetings: [Meeting], calendar: Calendar = .autoupdatingCurrent) -> [DayGroup] {
        var groups: [DayGroup] = []
        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.start)
            if groups.last?.day == day {
                groups[groups.count - 1].meetings.append(meeting)
            } else {
                groups.append(DayGroup(day: day, meetings: [meeting]))
            }
        }
        return groups
    }
}
