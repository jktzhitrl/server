// swift-tools-version:5.9
// NexoraCore – plattformunabhängiger Kern des NEXORA Samplers:
// DSP, Sampler-Engine, Sequencer, Datenmodelle, Presets, Export, MIDI-Parsing.
// Keine externen Abhängigkeiten. Auf macOS werden Accelerate und AVFoundation genutzt,
// auf anderen Plattformen (z. B. für CI-Tests unter Linux) skalare Fallbacks.
import PackageDescription

let package = Package(
    name: "NexoraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NexoraCore", targets: ["NexoraCore"])
    ],
    targets: [
        .target(
            name: "NexoraCore",
            path: "Sources/NexoraCore",
            swiftSettings: [
                // Der Audio-Kern wird auch in Debug-Builds optimiert übersetzt, damit die
                // Echtzeit-Wiedergabe beim Entwickeln in Xcode nicht aussetzt.
                .unsafeFlags(["-O"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "NexoraCoreTests",
            dependencies: ["NexoraCore"],
            path: "Tests/NexoraCoreTests"
        )
    ]
)
