import AppKit
import EventKit
import NextMeetingCore

enum CalendarAccess {
    case granted, notDetermined, denied
}

struct CalendarInfo {
    var id: String
    var title: String
    var color: NSColor
    /// Account name, e.g. "iCloud" or "work@example.com".
    var account: String
}

/// Reads the on-device calendar database through EventKit. EventKit talks to the local
/// calendar daemon; syncing with iCloud/Google/Exchange is done by macOS, not by this app.
@MainActor
final class CalendarService {
    let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied // denied, restricted, writeOnly
        }
    }

    func requestAccess() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        if granted { store.reset() }
        return granted
    }

    /// All event calendars, grouped by account then sorted by title.
    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: $0.color, account: $0.source?.title ?? "Other") }
            .sorted { a, b in
                let byAccount = a.account.localizedStandardCompare(b.account)
                if byAccount != .orderedSame { return byAccount == .orderedAscending }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    /// Events overlapping the next `days` days in calendars not in `excluded`.
    func meetings(excluding excluded: Set<String>, now: Date, days: Int = 7) -> [Meeting] {
        guard access == .granted else { return [] }
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        // An empty array would mean "all calendars" to EventKit.
        guard !calendars.isEmpty else { return [] }

        let start = now.addingTimeInterval(-24 * 60 * 60) // catch long events already in progress
        let end = now.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(Meeting.init(event:))
    }
}

extension Meeting {
    init(event: EKEvent) {
        let me = event.attendees?.first { $0.isCurrentUser }
        self.init(
            // eventIdentifier is shared by all occurrences of a recurring event.
            id: "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isDeclined: me?.participantStatus == .declined,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            url: event.url,
            location: event.location,
            notes: event.notes
        )
    }
}
