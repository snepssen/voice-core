import Foundation
import XCTest
@testable import VoiceCore

final class VoiceCoreTests: XCTestCase {
    static func fixture(_ name: String) throws -> [[String]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// The shared espeak-ng build says what Voice Forge's said, word for word:
    /// the NORTH/FORCE vowel, clause marks, a spaced em dash.
    func testEnglishMatchesVoiceForge() throws {
        let espeak = try EspeakPhonemizer(dataDirectory: XCTUnwrap(EspeakData.directory), voice: "en-us")
        for row in try Self.fixture("en_us_phonemes.tsv") {
            XCTAssertEqual(try espeak.phonemize(row[0], dropFinalStop: true), row[1], row[0])
        }
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
