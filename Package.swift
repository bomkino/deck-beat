// swift-tools-version: 6.0
//
// Deck Beat: your deck, lit up by your music. A native Mac app from pitch.dog,
// on the same engine as Drift, Galileo and Backdrop.
//
//   RenderCore   GPU context, colour science, finishing, readback, video writing
//   BackdropKit  generative background engine (Metal, analytic, loopable)
//   StageKit     the shared stage: renderer, scene engine and export
//   StudioKit    shared design language, controls and window chrome
//   BeatKit      listening to a song, and the grid that answers it
//
//   Deck Beat    the app
//   beat-lab     headless checks and renders, for CI and visual review
//
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "DeckBeat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RenderCore", targets: ["RenderCore"]),
        .library(name: "BackdropKit", targets: ["BackdropKit"]),
        .library(name: "StageKit", targets: ["StageKit"]),
        .library(name: "StudioKit", targets: ["StudioKit"]),
        .library(name: "BeatKit", targets: ["BeatKit"]),
        .executable(name: "DeckBeat", targets: ["DeckBeatApp"]),
        .executable(name: "beat-lab", targets: ["DeckBeatLab"]),
    ],
    targets: [
        .target(name: "RenderCore", swiftSettings: settings),
        .target(name: "BackdropKit", dependencies: ["RenderCore"], swiftSettings: settings),
        .target(name: "StageKit", dependencies: ["RenderCore", "BackdropKit"], swiftSettings: settings),
        .target(name: "StudioKit", dependencies: ["RenderCore", "BackdropKit", "StageKit"], swiftSettings: settings),
        .target(name: "BeatKit", dependencies: ["RenderCore", "BackdropKit", "StageKit"], swiftSettings: settings),
        .executableTarget(name: "DeckBeatApp", dependencies: ["StudioKit", "BeatKit"], swiftSettings: settings),
        .executableTarget(name: "DeckBeatLab", dependencies: ["RenderCore", "StageKit", "BeatKit"], swiftSettings: settings),
    ]
)
