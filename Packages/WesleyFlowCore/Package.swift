// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WesleyFlowCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "VoiceInput", targets: ["VoiceInput"]),
        .library(name: "TaskExecution", targets: ["TaskExecution"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "SystemOperations", targets: ["SystemOperations"]),
        .library(name: "CodingAgents", targets: ["CodingAgents"]),
        .library(name: "Workspace", targets: ["Workspace"]),
        .library(name: "ModelProviders", targets: ["ModelProviders"]),
        .executable(name: "PersonalAgentHarness", targets: ["PersonalAgentHarness"]),
        .executable(name: "OllamaEvaluation", targets: ["OllamaEvaluation"])
    ],
    targets: [
        .executableTarget(name: "PersonalAgentHarness", dependencies: ["Domain", "SystemOperations"], path: "Tools/PersonalAgentHarness"),
        .executableTarget(name: "OllamaEvaluation", dependencies: ["Domain", "ModelProviders", "Workspace", "SystemOperations"], path: "Tools/OllamaEvaluation", resources: [.copy("Corpus.json")]),
        .target(name: "Domain"),
        .binaryTarget(name: "whisper", url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-v1.8.2-xcframework.zip", checksum: "3ffeec1df254d908f01ee3d87bf0aedb8fbc8f29cbf50dc8702741bb85381385"),
        .target(name: "CSpeakerRuntime"),
        .target(name: "VoiceInput", dependencies: ["Domain", "whisper", "CSpeakerRuntime"], resources: [.copy("Notices")]),
        .testTarget(name: "VoiceInputTests", dependencies: ["Domain", "VoiceInput"],
                    linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])]),
        .target(name: "ModelProviders", dependencies: ["Domain"]),
        .target(name: "Workspace", dependencies: ["Domain"]),
        .target(name: "CodingAgents", dependencies: ["Domain"]),
        .target(name: "TaskExecution", dependencies: ["Domain"]),
        .target(name: "Persistence", dependencies: ["Domain"]),
        .target(name: "SystemOperations", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "WorkspaceTests", dependencies: ["Domain", "Workspace", "SystemOperations", "ModelProviders", "TaskExecution"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CodingAgentsTests", dependencies: ["Domain", "CodingAgents"], resources: [.copy("Fixtures")]),
        .testTarget(name: "Phase1ATests", dependencies: ["Domain", "TaskExecution", "Persistence", "SystemOperations"])
    ],
    swiftLanguageModes: [.v6]
)
