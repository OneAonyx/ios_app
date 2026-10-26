// swift-tools-version: 6.0
//
// TagwerkCore: reine Fachlogik ohne Apple-Frameworks.
// Läuft auf iOS und unter Linux, damit die Tests ohne Mac laufen.

import PackageDescription

let package = Package(
    name: "TagwerkCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TagwerkCore", targets: ["TagwerkCore"]),
    ],
    targets: [
        .target(
            name: "TagwerkCore",
            // Übungsbibliothek und Startplan (JSON), auch unter Linux testbar.
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TagwerkCoreTests", dependencies: ["TagwerkCore"]),
    ]
)
