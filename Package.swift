// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "notes",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "Notes", targets: ["Notes"]),
        .executable(name: "notesctl", targets: ["notesctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Naveen-Kannan/flow.git", revision: "38d15b6ee157e9cae30f1b489b2734c7f5be1c84"),
        // Consumer roots must pin FluidAudio's tokenizer dependency on Swift 6.1 .
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.6"),
    ],
    targets: [
        .target(name: "Notes", dependencies: [.product(name: "Flow", package: "flow")]),
        .executableTarget(name: "notesctl", dependencies: ["Notes"]),
        .testTarget(name: "NotesTests", dependencies: ["Notes"]),
    ],
    swiftLanguageModes: [.v5]
)
