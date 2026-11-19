# NextMeeting

A small macOS menu bar app that shows your next meeting from Apple Calendar and gives you a one-click join link when the meeting is a video call. It runs entirely on your Mac and makes **no network calls**.

```
Standup · in 12m
```

## Features

- **Menu bar title**: `Standup · in 12m`, `Standup · 2:30 PM`, `Standup · Tue 9:00 AM` or `Standup · now`. A meeting that started in the last 10 minutes stays as "next" so you can still join it. If several started in that window, the earliest is in the title and all of them are listed at the top of the menu, each with its own join link. All-day, cancelled and declined events are skipped.
- **Join link**: `Join Zoom Meeting` (⌘J) and `Copy Meeting Link` (⌘C) when a link is found. Recognizes Zoom, Google Meet, Teams, Webex, FaceTime, Slack huddles, Whereby, Around, GoTo, BlueJeans and Chime links in the event URL, location or notes. Otherwise it uses the event URL or a URL in the location. Other links in the notes (docs, PRs) are ignored.
- **Later**: the rest of today and tomorrow (up to 8), under `Today` / `Tomorrow`. Click a row with a 🎥 icon to join it.
- **Calendars ▸**: choose which calendars count. New calendars are on by default.
- **Launch at Login**.

## Requirements

- macOS 14 or later
- Swift 6 toolchain. The Command Line Tools are enough; Xcode is not required.

## Build & install

```sh
swift test                         # unit tests (Swift Testing)
scripts/build-app.sh               # -> build/NextMeeting.app
scripts/build-app.sh --install     # also copies to /Applications
open /Applications/NextMeeting.app
```

On first launch macOS asks for Calendar access. If you deny it, the menu shows **Open Calendar Privacy Settings…** so you can turn it on later in System Settings → Privacy & Security → Calendars.

## Privacy: how "no network" is enforced

- The app is **sandboxed** with only two entitlements: `app-sandbox` and `personal-information.calendars`. Without `com.apple.security.network.client`, the kernel blocks any socket the process tries to open.
- Events are read with **EventKit** from the calendar database on your Mac, the same one Calendar.app uses. macOS handles syncing with iCloud, Google or Exchange; this app never talks to those services.
- Opening a join link hands the URL to macOS (`NSWorkspace.open`), so your browser or Zoom/Teams makes the connection, not NextMeeting.

To check this yourself:

```sh
codesign -d --entitlements - /Applications/NextMeeting.app   # sandbox + calendars only
grep -rE 'URLSession|import Network' Sources                 # no output
lsof -i -a -p "$(pgrep -x NextMeeting)"                      # no sockets
```

## Signing

By default `build-app.sh` signs **ad-hoc** (`SIGN_IDENTITY=-`). That works, but it has two drawbacks:

1. macOS ties the Calendar permission to the code signature, and an ad-hoc signature changes with every build. **Each rebuild asks for Calendar access again.**
2. **Launch at Login** (`SMAppService`) may refuse to register an ad-hoc-signed app, or forget it after a rebuild. It also needs the app at a stable path, which is why you should install to `/Applications`.

A self-signed code-signing certificate solves both:

1. Open **Keychain Access** → *Keychain Access* menu → *Certificate Assistant* → *Create a Certificate…*
2. Name: `NextMeeting Local Signing`, Identity Type: *Self Signed Root*, Certificate Type: *Code Signing*. Click Create.
3. Build with it:

   ```sh
   SIGN_IDENTITY="NextMeeting Local Signing" scripts/build-app.sh --install
   ```

You'll need to grant Calendar access one more time. After that it persists across rebuilds.

## Layout

```
Sources/NextMeetingCore/   pure logic (no EventKit/AppKit), fully unit tested
  Meeting.swift              event model
  MeetingLinkDetector.swift  finds the join link
  NextMeetingSelector.swift  picks "next" and "later"
  TitleFormatter.swift       all user-visible strings
Sources/NextMeeting/       the app
  main.swift                 NSApplication setup (menu bar only, no Dock icon)
  CalendarService.swift      EventKit access + EKEvent → Meeting
  StatusItemController.swift menu bar title, menu, refresh triggers
  Settings.swift             excluded calendars (UserDefaults)
  LoginItem.swift            SMAppService wrapper
Resources/                 Info.plist, entitlements
scripts/build-app.sh       build, bundle, sign, install
```

The app refreshes on launch, when the calendar database changes, after the Mac wakes, when the clock or time zone changes, when you open the menu, and every 30 seconds to keep the countdown current.
