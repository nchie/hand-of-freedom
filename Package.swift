// swift-tools-version: 6.2
import PackageDescription

// Layout and dependency rules: docs/how-it-works.md.
let package = Package(
    name: "HandOfFreedom",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "HandOfFreedom", targets: ["HandOfFreedomApp"]),
        .executable(name: "hof", targets: ["hof"]),
    ],
    targets: [
        // The only places the private framework and IOHIDPostEvent appear.
        .target(name: "CMultitouchSupport"),
        .target(name: "CHIDInject", linkerSettings: [.linkedFramework("IOKit")]),

        // Pure gesture logic: standard library only.
        .target(name: "GestureCore"),
        // OS boundaries: touch source, injector, event tap, marker capture.
        .target(name: "PlatformBackends",
                dependencies: ["GestureCore", "CMultitouchSupport", "CHIDInject"],
                linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("ScreenCaptureKit"),
                                 .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo")]),
        // Wiring: hot loop, lock-free handoff, traces, replay, session helpers.
        .target(name: "Runtime",
                dependencies: ["GestureCore", "PlatformBackends"],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]),
        // The menu-bar app: SwiftUI views over Runtime's PipelineController.
        .executableTarget(name: "HandOfFreedomApp", dependencies: ["Runtime"],
                          swiftSettings: [.defaultIsolation(MainActor.self)]),
        // Developer CLI: log, record, replay, live, permissions, probe, check.
        .executableTarget(name: "hof", dependencies: ["Runtime"]),

        // Scripted touch sessions shared by the test targets.
        .target(name: "TestSupport", dependencies: ["GestureCore"], path: "Tests/Support"),
        .target(name: "AllocCounter", path: "Tests/AllocCounter"),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore", "TestSupport"]),
        .testTarget(name: "RuntimeTests", dependencies: ["Runtime", "PlatformBackends", "CMultitouchSupport", "TestSupport", "AllocCounter"]),
    ],
    swiftLanguageModes: [.v6]
)
