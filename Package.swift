// swift-tools-version: 6.0
import PackageDescription

// voice-core: the speech engine every snepssen app shares, from one source.
//
// Voice Forge, Gateway Forge and the Interpreter (interpreter-forge) each carried
// a copy of the same pieces, and the copies drifted: three espeak-ng builds of
// one pinned revision, the same 513 files of its data three times, a
// phonemizer in three versions, Polyphon in two languages. Each app now
// depends on this package at a version, and a release here is a version bump
// there (scripts/release.sh), checked by that app's own tests before it lands.
//
// What is shared is mechanism, not taste. Each app keeps its own policy as an
// option or above this package: Gateway Forge's respellings and its two
// trailing pads, Voice Forge's token layout and duration dials, the
// Interpreter's per-sentence ids for the polyglot voice. A change here must
// leave every app's output as it was, which the tests below hold it to.
//
// No voice is in here. Voices are published as releases of the repositories
// that train them (voice-polyglot), and fetched by the apps that speak them.
// espeak-ng is an XCFramework on Apple platforms and its own sources
// elsewhere (Sources/CEspeakNGLinux, the same commit and options); ONNX Runtime
// is Microsoft's Apple package there, and on Linux its C API, opened at run
// time from the library scripts/fetch-onnxruntime.sh fetches. The host that
// evaluates this manifest decides, as in speech-core.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let espeak: Target = .binaryTarget(name: "CEspeakNG", path: "Frameworks/CEspeakNG.xcframework")
let runtime: [Target.Dependency] = [
    .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
]
let extraTargets: [Target] = []
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.20.0"),
]
#else
let espeak: Target = .target(
    name: "CEspeakNG",
    path: "Sources/CEspeakNGLinux",
    exclude: ["COPYING", "README.md"],
    cSettings: [
        .headerSearchPath("ucd-tools"),
        .define("_FILE_OFFSET_BITS", to: "64"),
        .define("LIBESPEAK_NG_EXPORT", to: "1"),
        .define("PATH_ESPEAK_DATA", to: "\"/usr/share/espeak-ng-data\""),
    ],
    linkerSettings: [.linkedLibrary("m")])
let runtime: [Target.Dependency] = ["COnnxRuntime"]
let extraTargets: [Target] = [
    .target(name: "COnnxRuntime", path: "Sources/COnnxRuntimeLinux", exclude: ["LICENSE", "README.md"]),
]
let dependencies: [Package.Dependency] = []
#endif

let package = Package(
    name: "VoiceCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VoiceCore", targets: ["VoiceCore"]),
    ],
    dependencies: dependencies,
    targets: [
        // espeak-ng at piper1-gpl's commit 724808c, for macOS, iOS and the
        // simulator (scripts/build-espeak.sh), and from source elsewhere: the
        // revision and options every snepssen voice was trained through.
        espeak,
        .target(
            name: "VoiceCore",
            dependencies: ["CEspeakNG"] + runtime,
            // espeak-ng's data, byte-identical to what the voices were trained
            // with. Never the newer data piper-phonemize bundles: it moved the
            // NORTH/FORCE vowel and 8 of 35 common English words changed.
            resources: [.copy("Resources/espeak-ng-data")]),
        .testTarget(
            name: "VoiceCoreTests",
            dependencies: ["VoiceCore"],
            exclude: ["make_fixture.py"],
            resources: [.copy("Fixtures")]),
    ] + extraTargets
)
