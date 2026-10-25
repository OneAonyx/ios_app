// swift-tools-version: 6.0
//
// TagwerkKit: Apple-spezifischer Teil (SwiftUI, HealthKit, AlarmKit, WidgetKit …).
// Wird von App und Widget-Extension gemeinsam genutzt. Baut nur mit dem iOS-SDK.

import PackageDescription

let package = Package(
    name: "TagwerkKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "TagwerkKit", targets: ["TagwerkKit"]),
    ],
    dependencies: [
        .package(path: "../TagwerkCore"),
    ],
    targets: [
        .target(
            name: "TagwerkKit",
            dependencies: [.product(name: "TagwerkCore", package: "TagwerkCore")],
            // Swift-5-Modus für die Apple-Frameworks in Phase 0: Nebenläufigkeits-
            // Hinweise kommen als Warnung statt als Fehler. Umstellung auf Swift 6 in Phase 1.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
