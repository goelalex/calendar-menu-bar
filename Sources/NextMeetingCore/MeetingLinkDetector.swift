import Foundation

/// Video-call services we recognize by URL.
public enum MeetingProvider: String, Sendable, CaseIterable {
    case zoom, googleMeet, teams, webex, faceTime, slackHuddle, whereby, around, goTo, blueJeans, chime

    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Teams"
        case .webex: "Webex"
        case .faceTime: "FaceTime"
        case .slackHuddle: "Slack Huddle"
        case .whereby: "Whereby"
        case .around: "Around"
        case .goTo: "GoTo"
        case .blueJeans: "BlueJeans"
        case .chime: "Chime"
        }
    }

    /// Menu label for the join item, e.g. "Join Zoom Meeting".
    public var joinTitle: String {
        switch self {
        case .zoom: "Join Zoom Meeting"
        case .googleMeet: "Join Google Meet"
        case .teams: "Join Teams Meeting"
        case .webex: "Join Webex Meeting"
        case .faceTime: "Join FaceTime"
        case .slackHuddle: "Join Slack Huddle"
        case .whereby: "Join Whereby"
        case .around: "Join Around"
        case .goTo: "Join GoTo Meeting"
        case .blueJeans: "Join BlueJeans"
        case .chime: "Join Chime Meeting"
        }
    }

    /// Whether `url` is a meeting link for this provider.
    func matches(host: String, path: String) -> Bool {
        func on(_ domains: String...) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        let hasPath = path.count > 1
        switch self {
        case .zoom:
            return on("zoom.us", "zoomgov.com")
                && ["/j/", "/s/", "/w/", "/my/", "/wc/"].contains { path.hasPrefix($0) }
        case .googleMeet:
            return host == "meet.google.com" && hasPath
        case .teams:
            return on("teams.microsoft.com", "teams.live.com", "teams.microsoft.us")
                && (path.contains("meetup-join") || path.hasPrefix("/meet"))
        case .webex:
            guard on("webex.com") else { return false }
            let components = path.split(separator: "/")
            // Personal rooms and scheduled invitations, not help/download pages.
            return (components.count == 2 && ["meet", "join"].contains(components[0]))
                || (components.count == 2 && components[1] == "j.php")
        case .faceTime:
            return host == "facetime.apple.com" && path.hasPrefix("/join")
        case .slackHuddle:
            return on("slack.com") && path.contains("/huddle/")
        case .whereby:
            return on("whereby.com") && hasPath
        case .around:
            return on("around.co") && hasPath
        case .goTo:
            return on("goto.com", "gotomeeting.com", "gotomeet.me") && hasPath
        case .blueJeans:
            return on("bluejeans.com") && hasPath
        case .chime:
            return on("chime.aws") && hasPath
        }
    }
}

public struct MeetingLink: Sendable, Equatable {
    public var url: URL
    /// `nil` when the link was taken from the event URL/location without a recognized provider.
    public var provider: MeetingProvider?

    public init(url: URL, provider: MeetingProvider?) {
        self.url = url
        self.provider = provider
    }

    public var joinTitle: String { provider?.joinTitle ?? "Join Meeting" }
}

public enum MeetingLinkDetector {
    /// Picks the join link for an event:
    /// 1. the first URL (event URL, then location, then notes) that matches a known provider;
    /// 2. else the event URL, or a URL found in the location;
    /// 3. arbitrary URLs in notes are ignored — they are usually docs, not meetings.
    public static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let fromURL = url.flatMap(webURL).map { [$0] } ?? []
        let fromLocation = urls(in: location)
        let fromNotes = urls(in: notes)

        for candidate in fromURL + fromLocation + fromNotes {
            if let provider = provider(for: candidate) {
                return MeetingLink(url: candidate, provider: provider)
            }
        }
        if let fallback = fromURL.first ?? fromLocation.first {
            return MeetingLink(url: fallback, provider: nil)
        }
        return nil
    }

    public static func provider(for url: URL) -> MeetingProvider? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path().lowercased()
        return MeetingProvider.allCases.first { $0.matches(host: host, path: path) }
    }

    /// All http(s) URLs in `text`, in order of appearance.
    static func urls(in text: String?) -> [URL] {
        guard var text, !text.isEmpty else { return [] }
        text = normalizeHTMLLinks(in: text)
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            match.url.flatMap(webURL)
        }
    }

    /// Decode href values without rendering HTML or changing literal entities in plain URLs.
    /// Replacements stay in place so event/location/notes and first-link ordering is preserved.
    private static func normalizeHTMLLinks(in text: String) -> String {
        let result = NSMutableString(string: text)
        let matches = htmlLink.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = (1..<match.numberOfRanges)
                .map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }),
                let swiftRange = Range(range, in: text),
                let url = URL(string: decodeHTMLEntities(String(text[swiftRange]))),
                webURL(url) != nil else { continue }
            result.replaceCharacters(in: range, with: url.absoluteString)
        }
        return result as String
    }

    /// One pass: `&amp;amp;` becomes `&amp;`, never `&`. Percent escapes are untouched.
    private static func decodeHTMLEntities(_ text: String) -> String {
        let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"]
        let result = NSMutableString(string: text)
        for match in htmlEntity.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let entity = String(text[range])
            let replacement: String?
            if entity.hasPrefix("#") {
                let hex = entity.lowercased().hasPrefix("#x")
                let digits = entity.dropFirst(hex ? 2 : 1)
                replacement = UInt32(digits, radix: hex ? 16 : 10)
                    .flatMap(UnicodeScalar.init).map { String($0) }
            } else {
                replacement = named[entity.lowercased()]
            }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }

    private static let htmlLink = try! NSRegularExpression(
        pattern: #"<a\b[^>]*?\s+href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )
    private static let htmlEntity = try! NSRegularExpression(
        pattern: #"&(#x[0-9a-f]+|#[0-9]+|amp|quot|apos|lt|gt);"#,
        options: [.caseInsensitive]
    )

    /// Only hand http(s) links to the system; drops mailto:, tel:, file:, etc.
    private static func webURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    // NSDataDetector is Sendable (thread-safe), so one shared instance is fine.
    private static let detector: NSDataDetector = {
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
}
