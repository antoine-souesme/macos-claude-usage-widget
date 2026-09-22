// swift-tools-version: 6.0
import PackageDescription

// Trois cibles : la logique réutilisable, l'application de la barre de menus,
// et un petit programme de vérification qui remplace XCTest (absent sans Xcode).
let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(name: "ClaudeUsage", dependencies: ["ClaudeUsageCore"]),
        .executableTarget(name: "ClaudeUsageChecks", dependencies: ["ClaudeUsageCore"]),
    ]
)
