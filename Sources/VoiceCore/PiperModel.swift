import Foundation
import OnnxRuntimeBindings

/// A Piper voice: its config, its ONNX session, and one inference call.
///
/// The part of the engine every app had the same: Voice Forge's `infer`,
/// Gateway Forge's `renderOne` and the Interpreter's `Voice` each built the
/// same three tensors and read the same output. How the ids are laid out is
/// each app's own (Gateway Forge's two trailing pads, Voice Forge's token
/// layout and directed pauses, the polyglot voice's one run per sentence), so
/// `ids` here is only the plain layout, and anything else is passed in.
public final class PiperModel: @unchecked Sendable {
    /// The fields `piper.voice.PiperVoice` reads, decoded the same way, and a
    /// polyglot voice's own block.
    public struct Config: Decodable, Sendable {
        public struct Audio: Decodable, Sendable { public var sample_rate: Int }
        public struct Espeak: Decodable, Sendable { public var voice: String }
        public struct Inference: Decodable, Sendable {
            public var noise_scale: Double
            public var length_scale: Double
            public var noise_w: Double
        }
        public var audio: Audio
        public var espeak: Espeak
        public var inference: Inference
        public var phoneme_id_map: [String: [Int]]
        public var polyglot: Polyglot?
    }

    /// A voice-polyglot export: which languages it was trained on, each one's
    /// pace, and which release it is. Its text must go through `Polyphon`.
    public struct Polyglot: Decodable, Sendable {
        public var languages: [String]
        public var length_scale: [String: Double]?
        public var epoch: Int?
        public var status: String?
        public var release: String?
    }

    public enum Failure: LocalizedError {
        case noRuntime, noOutput
        public var errorDescription: String? {
            switch self {
            case .noRuntime: "The ONNX runtime failed to start."
            case .noOutput: "The voice produced no audio."
            }
        }
    }

    /// Voice Forge's per-token duration input; the stock graph has none.
    public static let durationFactorsInput = "vf_duration_factors"

    public let config: Config
    public var sampleRate: Double { Double(config.audio.sample_rate) }
    /// Whether the graph takes `durationFactorsInput`. One that does must be
    /// fed it, so a call without factors feeds ones, which reproduces the
    /// stock voice exactly.
    public let takesDurationFactors: Bool
    public let outputNames: Set<String>
    private let session: ORTSession
    // ORT's contract is one environment, created once, used from anywhere;
    // it is never mutated after this initialiser runs.
    private nonisolated(unsafe) static let env: ORTEnv? = try? ORTEnv(loggingLevel: .warning)

    /// - Parameters:
    ///   - model: the `.onnx`.
    ///   - config: its `.onnx.json`; by default the file beside it.
    public init(model: URL, config configURL: URL? = nil) throws {
        guard let env = Self.env else { throw Failure.noRuntime }
        let configURL = configURL ?? model.deletingPathExtension().appendingPathExtension("onnx.json")
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        session = try ORTSession(env: env, modelPath: model.path, sessionOptions: nil)
        takesDurationFactors = (try? session.inputNames())?.contains(Self.durationFactorsInput) ?? false
        outputNames = Set((try? session.outputNames()) ?? [])
    }

    /// Piper's plain layout: `^`, a pad, each known symbol and a pad, then
    /// `trailingPads` more pads and `$`. Unknown symbols are skipped, as
    /// `phonemes_to_ids` skips them.
    public func ids(_ phonemes: String, trailingPads: Int = 0) -> [Int] {
        Self.ids(phonemes, map: config.phoneme_id_map, trailingPads: trailingPads)
    }

    /// The same layout for any id map, without a loaded model.
    public static func ids(_ phonemes: String, map: [String: [Int]], trailingPads: Int = 0) -> [Int] {
        let pad = map["_"] ?? []
        var ids = (map["^"] ?? []) + pad
        for scalar in phonemes.unicodeScalars {
            guard let id = map[String(scalar)] else { continue }
            ids += id + pad
        }
        for _ in 0 ..< trailingPads { ids += pad }
        return ids + (map["$"] ?? [])
    }

    public struct Output: Sendable {
        /// Mono samples at `sampleRate`, as the graph wrote them.
        public var samples: [Float]
        /// Any other outputs asked for and present, by name.
        public var extra: [String: [Float]]
    }

    /// One inference call. Scales are in the model's order: noise, length,
    /// noise_w.
    public func infer(_ ids: [Int], noiseScale: Double, lengthScale: Double, noiseW: Double,
                      durationFactors: [Float]? = nil, extraOutputs: Set<String> = []) throws -> Output {
        let inputData = NSMutableData(bytes: ids.map { Int64($0) }, length: ids.count * 8)
        let input = try ORTValue(tensorData: inputData, elementType: .int64, shape: [1, NSNumber(value: ids.count)])
        var length = Int64(ids.count)
        let lengths = try ORTValue(tensorData: NSMutableData(bytes: &length, length: 8), elementType: .int64, shape: [1])
        var values: [Float] = [Float(noiseScale), Float(lengthScale), Float(noiseW)]
        let scales = try ORTValue(tensorData: NSMutableData(bytes: &values, length: 12), elementType: .float, shape: [3])

        var inputs = ["input": input, "input_lengths": lengths, "scales": scales]
        if takesDurationFactors {
            var factors = durationFactors ?? [Float](repeating: 1, count: ids.count)
            let data = NSMutableData(bytes: &factors, length: factors.count * MemoryLayout<Float>.size)
            inputs[Self.durationFactorsInput] = try ORTValue(tensorData: data, elementType: .float,
                                                             shape: [1, 1, NSNumber(value: factors.count)])
        }
        let wanted = Set(["output"]).union(extraOutputs.intersection(outputNames))
        let outputs = try session.run(withInputs: inputs, outputNames: wanted, runOptions: nil)
        guard outputs["output"] != nil else { throw Failure.noOutput }

        func floats(_ value: ORTValue?) -> [Float] {
            guard let value, let data = try? value.tensorData() as Data else { return [] }
            let count = data.count / MemoryLayout<Float>.size
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        }
        var extra: [String: [Float]] = [:]
        for name in wanted where name != "output" { extra[name] = floats(outputs[name]) }
        return Output(samples: floats(outputs["output"]), extra: extra)
    }
}
