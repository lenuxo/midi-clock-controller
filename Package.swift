// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MIDIClockController",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MIDIClockController", targets: ["MIDIClockController"])],
    targets: [
        .target(name: "ClockCore"),
        .executableTarget(name: "MIDIClockController", dependencies: ["ClockCore"]),
        .testTarget(name: "ClockCoreTests", dependencies: ["ClockCore"]),
        .testTarget(name: "ControllerTests", dependencies: ["MIDIClockController", "ClockCore"])
    ]
)
