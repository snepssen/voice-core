import CEspeakNG
import Foundation

/// Text to phonemes, via espeak-ng (CEspeakNG).
///
/// The one phonemizer of Voice Forge, Gateway Forge and the Interpreter, which
/// each carried a copy until voice-core. Where the copies differed it was
/// policy, and policy is an option here: an app's `respellings` (Gateway
/// Forge's `I-There` and `REBAL`) and whether an em dash gets the spaces
/// espeak needs to see it (`spacesEmDashes`, which Gateway Forge's voice was
/// never given). Everything else was the same code.
///
/// This is a direct Swift port of the C logic already verified working in
/// this project's Python tooling (`tools-python/piper1-gpl/src/piper/espeakbridge.c`)
/// — the clause-terminator constants and their masking are copied from there
/// exactly, not re-derived, since getting the bit arithmetic subtly wrong
/// here would silently misplace sentence/clause boundaries rather than fail
/// loudly.
public final class EspeakPhonemizer: @unchecked Sendable {
    public struct Clause {
        public var phonemes: String
        public var terminator: String
        public var endOfSentence: Bool
    }

    public enum PhonemizerError: LocalizedError {
        case initializationFailed
        case voiceNotFound(String)
        case allocationFailed

        public var errorDescription: String? {
            switch self {
            case .initializationFailed: return "espeak-ng failed to initialize"
            case .voiceNotFound(let voice): return "espeak-ng has no voice named \(voice)"
            case .allocationFailed: return "could not allocate a text buffer for phonemization"
            }
        }
    }

    // Mirrors espeakbridge.c's #defines exactly.
    private static let intonationFullStop: Int32 = 0x0000_0000
    private static let intonationComma: Int32 = 0x0000_1000
    private static let intonationQuestion: Int32 = 0x0000_2000
    private static let intonationExclamation: Int32 = 0x0000_3000
    private static let typeClause: Int32 = 0x0004_0000
    private static let typeSentence: Int32 = 0x0008_0000

    private static let clausePeriod = 40 | intonationFullStop | typeSentence
    private static let clauseQuestion = 40 | intonationQuestion | typeSentence
    private static let clauseExclamation = 45 | intonationExclamation | typeSentence
    private static let clauseComma = 20 | intonationComma | typeClause
    private static let clauseColon = 30 | intonationFullStop | typeClause
    private static let clauseSemicolon = 30 | intonationComma | typeClause

    // Initialization, voice selection and phonemization share process-global
    // C state. Per-Voice locks alone cannot protect two overlapping sessions.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var initialized = false
    /// The voice espeak-ng holds now: setting it reloads its rules, so a call
    /// only sets it when another phonemizer changed it.
    private nonisolated(unsafe) static var current: String?
    private let voiceName: String
    private let respellings: [(String, String)]
    private let spacesEmDashes: Bool

    /// - Parameters:
    ///   - dataDirectory: espeak-ng's data; `EspeakData.directory` is the one
    ///     the voices were trained with.
    ///   - voice: espeak-ng's voice, `en-us` for every snepssen English.
    ///   - respellings: authored term -> what espeak is given instead, applied
    ///     longest first so none eats a prefix of another. The authored text is
    ///     never touched; only espeak sees the respelling.
    ///   - spacesEmDashes: give an em dash the spaces espeak needs to see it as
    ///     a clause break (see `spacedEmDashes`).
    public init(dataDirectory: URL, voice: String, respellings: [(String, String)] = [],
                spacesEmDashes: Bool = true) throws {
        voiceName = voice
        self.respellings = respellings.sorted { $0.0.count > $1.0.count }
        self.spacesEmDashes = spacesEmDashes
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if !Self.initialized {
            let result = dataDirectory.path.withCString { path in
                espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, path, 0)
            }
            guard result >= 0 else { throw PhonemizerError.initializationFailed }
            Self.initialized = true
        }
        try Self.select(voice)
    }

    /// Under `lock`.
    private static func select(_ voice: String) throws {
        guard current != voice else { return }
        let status = voice.withCString { espeak_SetVoiceByName($0) }
        guard status == EE_OK else { throw PhonemizerError.voiceNotFound(voice) }
        current = voice
    }

    /// What espeak is given for `text`: this phonemizer's respellings, longest
    /// first. With none, the text itself; a general tool should not rewrite
    /// the words it was given, and only an app with its own vocabulary passes
    /// any.
    func respelled(_ text: String) -> String {
        var out = text
        for (term, respelling) in respellings { out = out.replacingOccurrences(of: term, with: respelling) }
        return out
    }

    /// Text to phoneme clauses -- each roughly a sentence or sub-clause,
    /// carrying its own terminator punctuation and whether it ends a sentence.
    public func clauses(for text: String) throws -> [Clause] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try Self.select(voiceName)
        let given = respelled(text)
        guard let buffer = strdup(spacesEmDashes ? Self.spacedEmDashes(given) : given)
        else { throw PhonemizerError.allocationFailed }
        defer { free(buffer) }

        var out: [Clause] = []
        var cursor: UnsafeRawPointer? = UnsafeRawPointer(buffer)
        while cursor != nil {
            var terminator: Int32 = 0
            guard let phonemesPtr = espeak_TextToPhonemesWithTerminator(
                &cursor, espeakCHARS_AUTO, espeakPHONEMES_IPA, &terminator
            ) else { break }

            let phonemes = String(cString: phonemesPtr)
            let masked = terminator & 0x000F_FFFF
            let terminatorStr: String
            switch masked {
            case Self.clausePeriod: terminatorStr = "."
            case Self.clauseQuestion: terminatorStr = "?"
            case Self.clauseExclamation: terminatorStr = "!"
            case Self.clauseComma: terminatorStr = ","
            case Self.clauseColon: terminatorStr = ":"
            case Self.clauseSemicolon: terminatorStr = ";"
            default: terminatorStr = ""
            }
            let endOfSentence = (terminator & Self.typeSentence) == Self.typeSentence
            out.append(Clause(phonemes: phonemes, terminator: terminatorStr, endOfSentence: endOfSentence))
        }
        return out
    }

    /// One flattened phoneme string for a whole passage — deliberately not
    /// split back into per-sentence pieces. Splitting into independent
    /// inference calls is exactly what caused the sentence-boundary glitch
    /// found this session (each chunk starts cold, with no real audio
    /// context); the fix was architectural, not a phonemizer concern, but it
    /// means this is the one method `PiperSpeechEngine` should call.
    /// - Parameter dropFinalStop: drop the very last `.` terminator, keeping
    ///   every interior one. See `PiperSpeechEngine.dropFinalFullStop`.
    public func phonemize(_ text: String, dropFinalStop: Bool = false) throws -> String {
        var result = ""
        for clause in try clauses(for: text) {
            // Strip (lang) switch flags the same way phonemize_espeak.py does
            // -- they surround words from a language other than the current
            // voice and aren't phonemes themselves.
            var stripped = clause.phonemes
            while let open = stripped.firstIndex(of: "("),
                  let close = stripped[open...].firstIndex(of: ")") {
                stripped.removeSubrange(open...close)
            }
            result += stripped + clause.terminator
            // A space after **every** terminator, not only the comma-like
            // ones. Flattening used to join sentences bare -- `hˈɪɹ.aɪ
            // wˈɛlkʌm` -- which is a shape the model never saw in training,
            // since Piper phonemizes one sentence at a time. `campfire-calling`
            // is the case that proved it costs something: the owner heard a
            // phantom "-eth" on "I welcome connection" in all eight draws of
            // the flattened line, and none at all when that sentence was
            // rendered on its own.
            if !clause.terminator.isEmpty { result += " " }
        }
        result = result.trimmingCharacters(in: .whitespaces)
        // Only a full stop, and only the final one: `?` and `!` carry meaning
        // this voice should keep, and interior stops are what separate
        // sentences inside one flattened call.
        if dropFinalStop, result.hasSuffix(".") {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result.decomposedStringWithCanonicalMapping
    }

    /// Give an em dash the spaces espeak needs in order to see it.
    ///
    /// **Measured, not assumed.** `quiet — and` phonemizes to `kwˈaɪət; ænd` —
    /// espeak turns a spaced em dash into a semicolon clause break, which is
    /// why `;` and `—` calibrate to the same number. `quiet—and` phonemizes to
    /// `kwˈaɪət ænd`, byte-identical to writing no dash at all. The mark is
    /// simply dropped.
    ///
    /// That mattered because the pause dial names `—` among the marks it gives
    /// room to. For `word—word`, which is how most people type an em dash, it
    /// was giving room to a break that did not exist. A control that names a
    /// mark has to make that mark work.
    ///
    /// This is whitespace around punctuation, not a respelling: no word is
    /// changed, and the dash does what it visibly means. A hyphen is left
    /// alone — it joins rather than separates, and espeak correctly runs
    /// `hyphenated-words` together as one phoneme run.
    static func spacedEmDashes(_ text: String) -> String {
        guard text.contains("—") else { return text }
        var out = ""
        var pendingSpace = false
        for ch in text {
            if ch == "—" {
                if !out.hasSuffix(" ") { out += " " }
                out += "—"
                pendingSpace = true
            } else if pendingSpace {
                out += ch == " " ? " " : " \(ch)"
                pendingSpace = false
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
