import AppKit
import NextMeetingCore
import ServiceManagement

/// Owns the menu bar item: keeps the title current and builds the dropdown.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let service = CalendarService()
    private let settings = Settings()
    private let formatter = TitleFormatter()
    private var selection = MeetingSelection.empty
    private var isMenuOpen = false
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        observeChanges()
        refresh()

        if service.access == .notDetermined {
            Task { await requestAccess() }
        }
    }

    // MARK: - Refresh

    private func observeChanges() {
        let local = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let triggers: [(NotificationCenter, Notification.Name, AnyObject?)] = [
            (local, .EKEventStoreChanged, service.store),
            (local, .NSSystemClockDidChange, nil),
            (local, .NSSystemTimeZoneDidChange, nil),
            (local, .NSCalendarDayChanged, nil),
            (workspace, NSWorkspace.didWakeNotification, nil),
        ]
        for (center, name, object) in triggers {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center, token))
        }

        // Keeps the "in 12m" countdown current. `.common` so it also ticks while the menu is open.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let now = Date()
        if service.access == .granted {
            let meetings = service.meetings(excluding: settings.excludedCalendarIDs, now: now)
            selection = NextMeetingSelector.select(meetings, now: now)
        } else {
            selection = .empty
        }
        updateTitle(now: now)
        // Don't swap items out from under the user; the menu is rebuilt on the next open.
        if !isMenuOpen { rebuildMenu(now: now) }
    }

    private func updateTitle(now: Date) {
        guard let button = statusItem.button else { return }
        if service.access != .granted {
            button.image = nil
            button.title = "Calendar access needed"
        } else if let next = selection.next {
            button.image = nil
            button.title = formatter.statusTitle(for: next, now: now)
        } else {
            button.title = ""
            button.image = Self.symbol("calendar", description: "No upcoming meetings")
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isMenuOpen = false
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu { isMenuOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isMenuOpen = false
        // Bring items like "in 3m" back in sync with the title after the menu was held open.
        rebuildMenu(now: Date())
    }

    // MARK: - Menu

    private func rebuildMenu(now: Date) {
        menu.removeAllItems()

        switch service.access {
        case .granted:
            addNextMeetingSection(now: now)
            addLaterSection(now: now)
            menu.addItem(.separator())
            menu.addItem(calendarsItem())
        case .notDetermined:
            menu.addItem(Self.info("NextMeeting needs access to your calendars."))
            menu.addItem(item("Grant Calendar Access…", #selector(grantAccess)))
        case .denied:
            menu.addItem(Self.info("Calendar access is turned off for NextMeeting."))
            menu.addItem(item("Open Calendar Privacy Settings…", #selector(openPrivacySettings)))
        }

        menu.addItem(launchAtLoginItem())
        menu.addItem(.separator())
        menu.addItem(item("Quit NextMeeting", #selector(quit), key: "q"))
    }

    private func addNextMeetingSection(now: Date) {
        guard let next = selection.next else {
            menu.addItem(Self.info("No upcoming meetings"))
            return
        }
        addMeetingBlock(next, now: now, shortcuts: true)
        // Overlapping meetings that also just started: each gets its own block and join link.
        for meeting in selection.alsoJoinable {
            menu.addItem(.separator())
            addMeetingBlock(meeting, now: now, shortcuts: false)
        }
    }

    /// Title, time range and calendar rows, then Join / Copy when the meeting has a link.
    /// ⌘J / ⌘C go to the first block only.
    private func addMeetingBlock(_ meeting: Meeting, now: Date, shortcuts: Bool) {
        let title = Self.info("")
        title.attributedTitle = NSAttributedString(
            string: formatter.menuTitle(for: meeting),
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        menu.addItem(title)
        menu.addItem(Self.info(formatter.timeRange(for: meeting, now: now)))
        if !meeting.calendarTitle.isEmpty {
            menu.addItem(Self.info(meeting.calendarTitle))
        }

        if let link = meeting.link {
            let join = item(link.joinTitle, #selector(openLink(_:)), key: shortcuts ? "j" : "")
            join.representedObject = link.url
            join.image = Self.symbol("video", description: "Video call")
            menu.addItem(join)

            let copy = item("Copy Meeting Link", #selector(copyLink(_:)), key: shortcuts ? "c" : "")
            copy.representedObject = link.url
            menu.addItem(copy)
        }
    }

    private func addLaterSection(now: Date) {
        let groups = NextMeetingSelector.groupByDay(selection.later)
        guard !groups.isEmpty else { return }
        menu.addItem(.separator())
        for group in groups {
            menu.addItem(.sectionHeader(title: formatter.dayName(for: group.day, now: now)))
            for meeting in group.meetings {
                let row = NSMenuItem(title: formatter.laterRow(for: meeting), action: nil, keyEquivalent: "")
                if let link = meeting.link {
                    row.target = self
                    row.action = #selector(openLink(_:))
                    row.representedObject = link.url
                    row.image = Self.symbol("video", description: "Has a meeting link")
                    row.toolTip = link.joinTitle
                }
                // Rows without a link are informational: enabled so they read normally, but no action.
                row.isEnabled = true
                menu.addItem(row)
            }
        }
    }

    private func calendarsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let calendars = service.calendars()
        var account: String?
        for calendar in calendars {
            if calendar.account != account {
                account = calendar.account
                submenu.addItem(.sectionHeader(title: calendar.account))
            }
            let row = item(calendar.title, #selector(toggleCalendar(_:)))
            row.representedObject = calendar.id
            row.state = settings.isCalendarEnabled(calendar.id) ? .on : .off
            row.image = Self.dot(calendar.color)
            submenu.addItem(row)
        }
        if calendars.isEmpty {
            submenu.addItem(Self.info("No calendars"))
        }

        let parent = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func launchAtLoginItem() -> NSMenuItem {
        let row = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch LoginItem.status {
        case .enabled: row.state = .on
        case .requiresApproval: row.state = .mixed
        default: row.state = .off
        }
        return row
    }

    // MARK: - Actions

    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        // The browser / Zoom / Teams app makes the connection, not NextMeeting.
        NSWorkspace.shared.open(url)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func toggleCalendar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.toggleCalendar(id)
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        let status = LoginItem.status
        if status == .requiresApproval {
            LoginItem.openSystemSettings()
            return
        }
        do {
            try LoginItem.setEnabled(status != .enabled)
            if LoginItem.status == .requiresApproval { LoginItem.openSystemSettings() }
        } catch {
            showAlert(
                "Couldn't change Launch at Login",
                "\(error.localizedDescription)\n\nMake sure NextMeeting is in /Applications. If it still fails, sign the app with a stable identity (see README)."
            )
        }
        rebuildMenu(now: Date())
    }

    @objc private func grantAccess() {
        Task { await requestAccess() }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestAccess() async {
        NSApp.activate()
        _ = await service.requestAccess()
        refresh()
    }

    private func showAlert(_ message: String, _ info: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Helpers

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
    }
}
