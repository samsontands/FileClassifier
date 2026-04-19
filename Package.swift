// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileClassifier",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "FileClassifier",
            targets: ["FileClassifier"]
        ),
    ],
    targets: [
        // Pure classification / naming logic. No AppKit / Vision deps so
        // it stays trivial to unit-test.
        .target(
            name: "FileClassifierCore",
            path: "Sources/FileClassifierCore"
        ),
        .executableTarget(
            name: "FileClassifier",
            dependencies: ["FileClassifierCore"],
            path: "Sources/FileClassifier"
        ),
        .testTarget(
            name: "FileClassifierCoreTests",
            dependencies: ["FileClassifierCore"],
            path: "Tests/FileClassifierCoreTests"
        ),
    ]
)
