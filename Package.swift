// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MIDIClockController",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MIDIClockController", targets: ["MIDIClockController"])],
    targets: [
        .target(name: "AppLocalization", resources: [.process("Resources")]),
        .target(name: "CLink", exclude: ["vendor/README.md", "vendor/link/LICENSE.md", "vendor/link/GNU-GPL-v2.0.md", "vendor/asio/LICENSE_1_0.txt", "vendor/asio/COPYING"],
                sources: ["LinkAdapter.cpp"], publicHeadersPath: "include",
                cxxSettings: [.headerSearchPath("vendor/link/include"), .headerSearchPath("vendor/asio/include"),
                              .define("LINK_PLATFORM_MACOSX", to: "1"), .define("LINK_PLATFORM_UNIX", to: "1"),
                              .define("ASIO_STANDALONE", to: "1"), .define("ASIO_NO_TYPEID", to: "1"),
                              .define("ASIO_VERSION_NAMESPACE", to: "midi_clock_link_asio")]),
        .target(name: "ClockCore", dependencies: ["AppLocalization"]),
        .target(name: "LinkBridge", dependencies: ["CLink", "ClockCore"]),
        .executableTarget(name: "MIDIClockController", dependencies: ["ClockCore", "AppLocalization", "LinkBridge"],
                          resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "LinkBridgeTests", dependencies: ["LinkBridge", "ClockCore"]),
        .testTarget(name: "ClockCoreTests", dependencies: ["ClockCore", "LinkBridge"]),
        .testTarget(name: "LocalizationTests", dependencies: ["AppLocalization"]),
        .testTarget(name: "ControllerTests", dependencies: ["MIDIClockController", "ClockCore"])
    ],
    cxxLanguageStandard: .cxx17
)
