// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WesleyFlowCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "TaskExecution", targets: ["TaskExecution"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "SystemOperations", targets: ["SystemOperations"]),
        .library(name: "CodingAgents", targets: ["CodingAgents"]),
        .library(name: "Workspace", targets: ["Workspace"])
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Workspace", dependencies: ["Domain"]),
        .target(name: "CodingAgents", dependencies: ["Domain"]),
        .target(name: "TaskExecution", dependencies: ["Domain"]),
        .target(name: "Persistence", dependencies: ["Domain"]),
        .target(name: "SystemOperations", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "WorkspaceTests", dependencies: ["Domain", "Workspace", "SystemOperations"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CodingAgentsTests", dependencies: ["Domain", "CodingAgents"], resources: [.copy("Fixtures")]),
        .testTarget(name: "Phase1ATests", dependencies: ["Domain", "TaskExecution", "Persistence", "SystemOperations"])
    ],
    swiftLanguageModes: [.v6]
)
