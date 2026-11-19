// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextMeeting",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NextMeeting", targets: ["NextMeeting"]),
    ],
    targets: [
        // Pure logic: no EventKit, no AppKit. Everything here is unit tested.
        .target(name: "NextMeetingCore"),
        // The menu bar app: EventKit + AppKit glue.
        .executableTarget(
            name: "NextMeeting",
            dependencies: ["NextMeetingCore"]
        ),
        .testTarget(
            name: "NextMeetingCoreTests",
            dependencies: ["NextMeetingCore"]
        ),
    ]
)
