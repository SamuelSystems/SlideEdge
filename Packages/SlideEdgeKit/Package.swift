// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlideEdgeKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AppSettings", targets: ["AppSettings"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "TouchInput", targets: ["TouchInput"]),
        .library(name: "GestureEngine", targets: ["GestureEngine"]),
        .library(name: "SystemControls", targets: ["SystemControls"]),
        .library(name: "HUD", targets: ["HUD"]),
        .library(name: "CursorControl", targets: ["CursorControl"]),
        .library(name: "CornerActions", targets: ["CornerActions"]),
        .library(name: "Haptics", targets: ["Haptics"]),
        .library(name: "KeyActivity", targets: ["KeyActivity"]),
    ],
    targets: [
        .target(name: "GestureEngine"),
        .target(name: "AppSettings", dependencies: ["GestureEngine"]),
        .target(name: "Permissions"),
        .target(name: "CMultitouch"),
        .target(name: "TouchInput", dependencies: ["CMultitouch"]),
        .target(name: "CCoreBrightness"),
        .target(name: "SystemControls", dependencies: ["CCoreBrightness"]),
        .target(name: "HUD"),
        .target(name: "CursorControl"),
        .target(name: "CornerActions", dependencies: ["AppSettings"]),
        .target(name: "Haptics"),
        .target(name: "KeyActivity"),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"]),
        .testTarget(name: "TouchInputTests", dependencies: ["TouchInput"]),
        .testTarget(name: "GestureEngineTests", dependencies: ["GestureEngine"]),
        .testTarget(name: "SystemControlsTests", dependencies: ["SystemControls"]),
    ]
)
