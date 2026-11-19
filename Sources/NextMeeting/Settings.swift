import Foundation

/// Persisted preferences. Stores *excluded* calendars so calendars added later default to on.
@MainActor
final class Settings {
    private let defaults: UserDefaults
    private let excludedKey = "excludedCalendarIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: excludedKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: excludedKey) }
    }

    func isCalendarEnabled(_ id: String) -> Bool {
        !excludedCalendarIDs.contains(id)
    }

    func toggleCalendar(_ id: String) {
        if excludedCalendarIDs.contains(id) {
            excludedCalendarIDs.remove(id)
        } else {
            excludedCalendarIDs.insert(id)
        }
    }
}
