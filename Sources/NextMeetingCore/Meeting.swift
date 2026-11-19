import Foundation

/// A calendar event, reduced to what the app needs. Built from `EKEvent` in the app target
/// so that all selection/formatting logic can be tested without EventKit.
public struct Meeting: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCancelled: Bool
    /// The current user is an attendee and declined.
    public var isDeclined: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var url: URL?
    public var location: String?
    public var notes: String?
    /// Join link detected from `url`, `location` and `notes`.
    public private(set) var link: MeetingLink?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        calendarID: String = "",
        calendarTitle: String = "",
        url: URL? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.url = url
        self.location = location
        self.notes = notes
        self.link = MeetingLinkDetector.detect(url: url, location: location, notes: notes)
    }

    /// Title with a fallback for events that have none.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No title)" : trimmed
    }
}
