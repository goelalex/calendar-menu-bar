import Foundation
import Testing
@testable import NextMeetingCore

struct MeetingLinkDetectorTests {
    @Test(arguments: [
        ("https://us02web.zoom.us/j/81234567890?pwd=abc", MeetingProvider.zoom),
        ("https://zoom.us/my/alice", .zoom),
        ("https://meet.google.com/abc-defg-hij", .googleMeet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d", .teams),
        ("https://teams.live.com/meet/9312345", .teams),
        ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
        ("https://acme.webex.com/meet/alex", .webex),
        ("https://acme.my.webex.com/join/alex", .webex),
        ("https://facetime.apple.com/join#v=1&p=abc", .faceTime),
        ("https://app.slack.com/huddle/T123/C456", .slackHuddle),
        ("https://whereby.com/team-standup", .whereby),
        ("https://around.co/r/standup", .around),
        ("https://meet.goto.com/123456789", .goTo),
        ("https://global.gotomeeting.com/join/123456789", .goTo),
        ("https://bluejeans.com/123456", .blueJeans),
        ("https://app.chime.aws/meetings/1234567890", .chime),
    ])
    func recognizesProviders(url: String, provider: MeetingProvider) {
        #expect(MeetingLinkDetector.provider(for: URL(string: url)!) == provider)
    }

    @Test(arguments: [
        "https://zoom.us/download",
        "https://meet.google.com/",
        "https://teams.microsoft.com/l/channel/abc",
        "https://docs.google.com/document/d/abc",
        "https://notzoom.us/j/123",
        "https://help.webex.com/article/123",
        "https://www.webex.com/downloads.html",
        "https://acme.webex.com/meet/",
        "https://notwebex.com/meet/alex",
    ])
    func ignoresNonMeetingURLs(url: String) {
        #expect(MeetingLinkDetector.provider(for: URL(string: url)!) == nil)
    }

    @Test func findsProviderLinkInEventURL() {
        let link = MeetingLinkDetector.detect(url: URL(string: "https://zoom.us/j/123"), location: nil, notes: nil)
        #expect(link == MeetingLink(url: URL(string: "https://zoom.us/j/123")!, provider: .zoom))
        #expect(link?.joinTitle == "Join Zoom Meeting")
    }

    @Test func findsProviderLinkInLocation() {
        let link = MeetingLinkDetector.detect(url: nil, location: "Room 4 / https://meet.google.com/abc-defg-hij", notes: nil)
        #expect(link?.provider == .googleMeet)
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsProviderLinkInNotes() {
        let notes = """
        Agenda: https://docs.google.com/document/d/xyz
        Join: https://us06web.zoom.us/j/8812345678?pwd=Q2x
        """
        let link = MeetingLinkDetector.detect(url: nil, location: "Conference Room B", notes: notes)
        #expect(link?.provider == .zoom)
        #expect(link?.url.absoluteString == "https://us06web.zoom.us/j/8812345678?pwd=Q2x")
    }

    @Test func handlesAngleBracketWrappedTeamsLinks() {
        let notes = """
        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA2%40thread.v2/0?context=%7b%22Tid%22%3a%22abc%22%7d>
        Meeting ID: 123 456 789
        """
        let link = MeetingLinkDetector.detect(url: nil, location: "Microsoft Teams Meeting", notes: notes)
        #expect(link?.provider == .teams)
        #expect(link?.url.absoluteString ==
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA2%40thread.v2/0?context=%7b%22Tid%22%3a%22abc%22%7d")
    }

    @Test func findsLinkInsideHTMLNotes() {
        let notes = #"<p>Join with Google Meet: <a href="https://meet.google.com/xyz-abcd-efg">meet.google.com/xyz-abcd-efg</a></p>"#
        let link = MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)
        #expect(link?.provider == .googleMeet)
        #expect(link?.url.host() == "meet.google.com")
    }

    @Test(arguments: ["&amp;", "&#38;", "&#x26;"])
    func decodesHTMLQuerySeparators(separator: String) {
        let expected = "https://us02web.zoom.us/j/123?from=addon&pwd=secret&token=a%26b"
        for quote in ["\"", "'", ""] {
            let notes = "<a href=\(quote)https://us02web.zoom.us/j/123?from=addon\(separator)pwd=secret\(separator)token=a%26b\(quote)>Join Zoom</a>"
            let link = MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)
            #expect(link?.url.absoluteString == expected)
            #expect(link?.provider == .zoom)
        }
    }

    @Test func decodesHTMLAttributesOnlyOnce() {
        let notes = #"<a href="https://zoom.us/j/123?token=a&amp;amp;b">Join</a>"#
        let link = MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)
        #expect(link?.url.absoluteString == "https://zoom.us/j/123?token=a&amp;b")
    }

    @Test func preservesLiteralEntitiesInPlainURLs() {
        let raw = "https://zoom.us/j/123?token=a&amp;b"
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: raw)?.url.absoluteString == raw)
        #expect(MeetingLinkDetector.detect(url: URL(string: raw), location: nil, notes: nil)?.url.absoluteString == raw)
    }

    @Test func htmlLinksKeepSourceOrder() {
        let notes = #"First https://zoom.us/j/111 <a href="https://zoom.us/j/222?x=1&amp;pwd=secret">Second</a>"#
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)?.url.absoluteString == "https://zoom.us/j/111")
    }

    @Test func webexHelpDoesNotOverrideMeeting() {
        let help = "https://help.webex.com/article/123"
        let meeting = "https://acme.webex.com/meet/alex"
        let link = MeetingLinkDetector.detect(url: URL(string: help), location: help, notes: "Help: \(help) Join: \(meeting)")
        #expect(link == MeetingLink(url: URL(string: meeting)!, provider: .webex))
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: help) == nil)
    }

    @Test func providerLinkInNotesBeatsGenericEventURL() {
        let link = MeetingLinkDetector.detect(
            url: URL(string: "https://example.com/event/42"),
            location: nil,
            notes: "Zoom: https://zoom.us/j/999"
        )
        #expect(link?.provider == .zoom)
    }

    @Test func fallsBackToEventURL() {
        let link = MeetingLinkDetector.detect(url: URL(string: "https://example.com/call"), location: nil, notes: nil)
        #expect(link == MeetingLink(url: URL(string: "https://example.com/call")!, provider: nil))
        #expect(link?.joinTitle == "Join Meeting")
    }

    @Test func fallsBackToURLInLocation() {
        let link = MeetingLinkDetector.detect(url: nil, location: "https://jitsi.example.org/standup", notes: nil)
        #expect(link?.url.absoluteString == "https://jitsi.example.org/standup")
        #expect(link?.provider == nil)
    }

    @Test func ignoresArbitraryURLsInNotes() {
        let link = MeetingLinkDetector.detect(
            url: nil,
            location: "Room 12",
            notes: "Doc: https://docs.google.com/document/d/abc and https://github.com/org/repo/pull/1"
        )
        #expect(link == nil)
    }

    @Test func noLink() {
        #expect(MeetingLinkDetector.detect(url: nil, location: "Cafe", notes: "Bring laptops") == nil)
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: nil) == nil)
    }

    @Test func ignoresNonWebSchemes() {
        let link = MeetingLinkDetector.detect(url: URL(string: "file:///etc/passwd"), location: "mailto:a@b.com", notes: nil)
        #expect(link == nil)
    }

    @Test func meetingComputesLink() {
        let meeting = Fixtures.meeting("Sync", start: Fixtures.now, notes: "https://meet.google.com/aaa-bbbb-ccc")
        #expect(meeting.link?.provider == .googleMeet)
    }
}
