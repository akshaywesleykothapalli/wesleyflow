// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WesleyFlowCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "Domain", targets: ["Domain"])],
    targets: [
        .target(name: "Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"])
    ],
    swiftLanguageModes: [.v6]
)
