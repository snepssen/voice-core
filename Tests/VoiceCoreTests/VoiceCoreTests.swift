import Foundation
import XCTest
@testable import VoiceCore

final class VoiceCoreTests: XCTestCase {
    static func fixture(_ name: String) throws -> [[String]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// No library source reaches its resources through SwiftPM's generated
    /// `Bundle.module`: its search differs by toolchain and ends in
    /// `fatalError`, which shipped as a crash on first render in Gateway
    /// Forge 5.3.1. (Tests may use it; they always run from the build tree.)
    /// The data is still found, from wherever this run keeps the bundle.
    func testResourcesAreNotFoundThroughBundleModule() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var uses: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("Bundle" + ".module.") { uses.append(url.lastPathComponent) }
        }
        XCTAssertEqual(uses, [], "resources found through Bundle.module")
        let data = try XCTUnwrap(EspeakData.directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.appending(path: "phontab").path))
    }

    /// One inference call through the runtime this platform has: Microsoft's
    /// Apple package, or on Linux its C API from the library opened at run
    /// time. The fixture graph has a voice's inputs and returns the ids times
    /// the length scale (make_fixture.py), so the answer is known exactly.
    func testOneInferenceCallReadsBackWhatTheGraphComputes() throws {
        let model = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/piper_shape", withExtension: "onnx"))
        let voice: PiperModel
        do {
            voice = try PiperModel(model: model)
        } catch PiperModel.Failure.runtimeMissing(let why) {
            // CI sets this, so a runner without the library fails rather than skips.
            if ProcessInfo.processInfo.environment["VOICE_CORE_REQUIRE_RUNTIME"] == "1" {
                XCTFail("ONNX Runtime is required here: \(why)")
                return
            }
            throw XCTSkip("no ONNX Runtime library on this machine (\(why))")
        }
        XCTAssertFalse(voice.takesDurationFactors, "the fixture has no duration input")
        XCTAssertEqual(voice.outputNames, ["output"])
        let ids = voice.ids("aa")
        XCTAssertEqual(ids, [1, 0, 14, 0, 14, 0, 2])
        let out = try voice.infer(ids, noiseScale: 0.667, lengthScale: 1.5, noiseW: 0.8)
        XCTAssertEqual(out.samples, ids.map { Float($0) * 1.5 })
        XCTAssertEqual(out.extra, [:])
    }

    /// The shared espeak-ng build says what Voice Forge's said, word for word:
    /// the NORTH/FORCE vowel, clause marks, a spaced em dash.
    func testEnglishMatchesVoiceForge() throws {
        let espeak = try EspeakPhonemizer(dataDirectory: XCTUnwrap(EspeakData.directory), voice: "en-us")
        for row in try Self.fixture("en_us_phonemes.tsv") {
            XCTAssertEqual(try espeak.phonemize(row[0], dropFinalStop: true), row[1], row[0])
        }
    }

    /// Gateway Forge's voice, call for call: every sentence its engine sent
    /// before it moved onto voice-core, as phonemes and as ids, through its
    /// options and its two trailing pads.
    func testGatewayForgeCallsAreUnchanged() throws {
        let gateway = try EspeakPhonemizer(dataDirectory: XCTUnwrap(EspeakData.directory), voice: "en-us",
                                           respellings: [("I-There", "Eye-There"), ("REBAL", "Reeball")],
                                           spacesEmDashes: false)
        let mapURL = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/phoneme_id_map", withExtension: "json"))
        let map = try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: mapURL))
        var checked = 0
        for row in try Self.fixture("gateway_forge_calls.tsv") {
            let phonemes = try gateway.phonemize(row[0], dropFinalStop: true)
            XCTAssertEqual(phonemes, row[1], row[0])
            XCTAssertEqual(PiperModel.ids(phonemes, map: map, trailingPads: 2),
                           row[2].split(separator: " ").compactMap { Int($0) }, row[0])
            checked += 1
        }
        XCTAssertGreaterThan(checked, 300)
    }

    /// Gateway Forge's policy, as options: its two respellings, and no em-dash spacing.
    func testRespellingsAndEmDashesAreOptions() throws {
        let data = try XCTUnwrap(EspeakData.directory)
        let gateway = try EspeakPhonemizer(dataDirectory: data, voice: "en-us",
                                           respellings: [("I-There", "Eye-There"), ("REBAL", "Reeball")],
                                           spacesEmDashes: false)
        let plain = try EspeakPhonemizer(dataDirectory: data, voice: "en-us")
        XCTAssertEqual(try gateway.phonemize("I-There"), try plain.phonemize("Eye-There"))
        XCTAssertEqual(try gateway.phonemize("REBAL"), try plain.phonemize("Reeball"))
        XCTAssertEqual(try gateway.phonemize("quiet—and"), try plain.phonemize("quiet and"))
        XCTAssertNotEqual(try plain.phonemize("quiet—and"), try plain.phonemize("quiet and"))
    }

    /// Polyphon against voice-polyglot's Python, id for id.
    func testPolyphonMatchesTheTrainingPhonemizer() throws {
        let mapURL = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/phoneme_id_map", withExtension: "json"))
        let map = try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: mapURL))
        let data = try XCTUnwrap(EspeakData.directory)
        var phonemizers: [String: EspeakPhonemizer] = [:]
        var checked = 0
        for row in try Self.fixture("polyphon_ids.tsv") {
            let (language, text) = (row[0], row[1])
            let espeak = try phonemizers[language] ?? EspeakPhonemizer(dataDirectory: data, voice: Polyphon.espeakVoice(language))
            phonemizers[language] = espeak
            let got = Polyphon.ids(try Polyphon.sentences(text, language: language, espeak: espeak), map: map)
            XCTAssertEqual(got, row[2].split(separator: " ").compactMap { Int($0) }, "[\(language)] \(text)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 30)
    }

    /// espeak-ng ignores a data path longer than its buffer; a deep one is
    /// reached through a short link to the same folder.
    func testDeepDataPathIsReachable() throws {
        let data = try XCTUnwrap(EspeakData.directory)
        let deep = URL(fileURLWithPath: "/" + String(repeating: "deep-folder/", count: 16) + "espeak-ng-data")
        XCTAssertEqual(EspeakPhonemizer.reachable(data.deletingLastPathComponent().appending(path: "espeak-ng-data")).resolvingSymlinksInPath().path,
                       data.resolvingSymlinksInPath().path)
        let link = EspeakPhonemizer.reachable(deep)
        XCTAssertLessThan(link.path.utf8.count, 120)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), deep.path)
    }

    /// Two phonemizers in different languages, used in turn, each stay theirs.
    func testPhonemizersKeepTheirOwnVoice() throws {
        let data = try XCTUnwrap(EspeakData.directory)
        let english = try EspeakPhonemizer(dataDirectory: data, voice: "en-us")
        let before = try english.phonemize("Build the pattern.")
        let german = try EspeakPhonemizer(dataDirectory: data, voice: "de")
        _ = try german.phonemize("Treffen sich zwei Jäger.")
        XCTAssertEqual(try english.phonemize("Build the pattern."), before)
    }
}
