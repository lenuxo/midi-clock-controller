// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MIDIClockController",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MIDIClockController", targets: ["MIDIClockController"])],
    targets: [
        .target(name: "AppLocalization", resources: [.process("Resources")]),
        .target(name: "ClockCore", dependencies: ["AppLocalization"]),
        .executableTarget(name: "MIDIClockController", dependencies: ["ClockCore", "AppLocalization"],
                          resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "ClockCoreTests", dependencies: ["ClockCore"]),
        .testTarget(name: "LocalizationTests", dependencies: ["AppLocalization"]),
        .testTarget(name: "ControllerTests", dependencies: ["MIDIClockController", "ClockCore"])
    ]
)
