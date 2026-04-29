// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLess",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "OpenLess", targets: ["OpenLessApp"]),
        .library(name: "OpenLessCore", targets: ["OpenLessCore"]),
        .library(name: "OpenLessHotkey", targets: ["OpenLessHotkey"]),
        .library(name: "OpenLessUI", targets: ["OpenLessUI"]),
        .library(name: "OpenLessRecorder", targets: ["OpenLessRecorder"]),
        .library(name: "OpenLessASR", targets: ["OpenLessASR"]),
        .library(name: "OpenLessPolish", targets: ["OpenLessPolish"]),
        .library(name: "OpenLessInsertion", targets: ["OpenLessInsertion"]),
        .library(name: "OpenLessPersistence", targets: ["OpenLessPersistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(name: "OpenLessCore", path: "Sources/OpenLessCore"),
        .target(
            name: "OpenLessHotkey",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessHotkey"
        ),
        .target(
            name: "OpenLessUI",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessUI"
        ),
        .target(
            name: "OpenLessRecorder",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessRecorder"
        ),
        .target(
            name: "OpenLessASR",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessASR"
        ),
        .target(
            name: "OpenLessPolish",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessPolish"
        ),
        .target(
            name: "OpenLessInsertion",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessInsertion"
        ),
        .target(
            name: "OpenLessPersistence",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessPersistence"
        ),
        .executableTarget(
            name: "OpenLessApp",
            dependencies: [
                "OpenLessCore",
                "OpenLessHotkey",
                "OpenLessUI",
                "OpenLessRecorder",
                "OpenLessASR",
                "OpenLessPolish",
                "OpenLessInsertion",
                "OpenLessPersistence",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/OpenLessApp",
            // 让 dyld 能在 Contents/Frameworks/ 里找到嵌入的 Sparkle.framework。
            // SPM 默认不给 executable 加这个 rpath，需要显式注入。
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "OpenLessCoreTests",
            dependencies: ["OpenLessCore"],
            path: "Tests/OpenLessCoreTests"
        ),
        .testTarget(
            name: "OpenLessPolishTests",
            dependencies: ["OpenLessPolish"],
            path: "Tests/OpenLessPolishTests"
        ),
        .testTarget(
            name: "OpenLessAppTests",
            dependencies: ["OpenLessApp"],
            path: "Tests/OpenLessAppTests"
        ),
        .testTarget(
            name: "OpenLessPersistenceTests",
            dependencies: ["OpenLessPersistence", "OpenLessCore"],
            path: "Tests/OpenLessPersistenceTests"
        ),
        .testTarget(
            name: "OpenLessASRTests",
            dependencies: ["OpenLessASR", "OpenLessCore"],
            path: "Tests/OpenLessASRTests"
        ),
    ],
    // 暂留 Swift 5 语言模式，避免一次性吞掉 Swift 6 严格并发的全部改造。
    // 升 .v6 时需要重新审视 Recorder / VolcengineStreamingASR 等 @unchecked Sendable 类。
    swiftLanguageModes: [.v5]
)
