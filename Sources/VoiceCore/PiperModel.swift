import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#else
import COnnxRuntime
#endif

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
        /// Linux: no ONNX Runtime library was found where it is looked for.
        case runtimeMissing(String)
        /// Linux: the runtime refused a call, with its own message.
        case runtime(String)
        public var errorDescription: String? {
            switch self {
            case .noRuntime: "The ONNX runtime failed to start."
            case .noOutput: "The voice produced no audio."
            case .runtimeMissing(let why): "ONNX Runtime is not installed (\(why)). scripts/fetch-onnxruntime.sh fetches it."
            case .runtime(let message): "ONNX Runtime: \(message)"
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
    private let engine: Engine

    /// - Parameters:
    ///   - model: the `.onnx`.
    ///   - config: its `.onnx.json`; by default the file beside it.
    public init(model: URL, config configURL: URL? = nil) throws {
        let configURL = configURL ?? model.deletingPathExtension().appendingPathExtension("onnx.json")
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        engine = try Engine(model: model)
        takesDurationFactors = engine.inputNames.contains(Self.durationFactorsInput)
        outputNames = engine.outputNames
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
        var inputs: [Engine.Tensor] = [
            .int64("input", ids.map { Int64($0) }, shape: [1, ids.count]),
            .int64("input_lengths", [Int64(ids.count)], shape: [1]),
            .float("scales", [Float(noiseScale), Float(lengthScale), Float(noiseW)], shape: [3]),
        ]
        if takesDurationFactors {
            let factors = durationFactors ?? [Float](repeating: 1, count: ids.count)
            inputs.append(.float(Self.durationFactorsInput, factors, shape: [1, 1, factors.count]))
        }
        let wanted = Set(["output"]).union(extraOutputs.intersection(outputNames))
        let outputs = try engine.run(inputs, outputs: wanted)
        guard let samples = outputs["output"] else { throw Failure.noOutput }
        var extra: [String: [Float]] = [:]
        for name in wanted where name != "output" { extra[name] = outputs[name] ?? [] }
        return Output(samples: samples, extra: extra)
    }
}

// MARK: - The runtime, per platform

#if canImport(OnnxRuntimeBindings)
/// Microsoft's Apple package.
private final class Engine: @unchecked Sendable {
    enum Tensor {
        case int64(String, [Int64], shape: [Int])
        case float(String, [Float], shape: [Int])
    }

    let session: ORTSession
    let inputNames: Set<String>
    let outputNames: Set<String>
    // ORT's contract is one environment, created once, used from anywhere;
    // it is never mutated after this initialiser runs.
    private nonisolated(unsafe) static let env: ORTEnv? = try? ORTEnv(loggingLevel: .warning)

    init(model: URL) throws {
        guard let env = Self.env else { throw PiperModel.Failure.noRuntime }
        session = try ORTSession(env: env, modelPath: model.path, sessionOptions: nil)
        inputNames = Set((try? session.inputNames()) ?? [])
        outputNames = Set((try? session.outputNames()) ?? [])
    }

    func run(_ inputs: [Tensor], outputs wanted: Set<String>) throws -> [String: [Float]] {
        var values: [String: ORTValue] = [:]
        for tensor in inputs {
            switch tensor {
            case .int64(let name, var data, let shape):
                values[name] = try ORTValue(tensorData: NSMutableData(bytes: &data, length: data.count * 8),
                                            elementType: .int64, shape: shape.map { NSNumber(value: $0) })
            case .float(let name, var data, let shape):
                values[name] = try ORTValue(tensorData: NSMutableData(bytes: &data, length: data.count * 4),
                                            elementType: .float, shape: shape.map { NSNumber(value: $0) })
            }
        }
        let outputs = try session.run(withInputs: values, outputNames: wanted, runOptions: nil)
        var result: [String: [Float]] = [:]
        for (name, value) in outputs {
            guard let data = try? value.tensorData() as Data else { continue }
            let count = data.count / MemoryLayout<Float>.size
            result[name] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        }
        return result
    }
}
#else
/// ONNX Runtime's C API, from Microsoft's Linux library opened at run time.
private final class Engine: @unchecked Sendable {
    enum Tensor {
        case int64(String, [Int64], shape: [Int])
        case float(String, [Float], shape: [Int])
    }

    let session: OpaquePointer
    let inputNames: Set<String>
    let outputNames: Set<String>
    private let api: UnsafePointer<OrtApi>

    /// Where the library is looked for, first to last: `VOICE_CORE_ONNXRUNTIME`
    /// (a path to the `.so`), where `scripts/fetch-onnxruntime.sh` puts it, and
    /// the system's library path.
    static var candidates: [String] {
        let env = ProcessInfo.processInfo.environment
        let data = env["XDG_DATA_HOME"] ?? (NSHomeDirectory() + "/.local/share")
        return [env["VOICE_CORE_ONNXRUNTIME"],
                data + "/snepssen/onnxruntime/1.24.2/lib/libonnxruntime.so",
                "libonnxruntime.so.1", "libonnxruntime.so"].compactMap { $0 }
    }

    /// The API table, loaded once for the process, or why it could not be.
    private nonisolated(unsafe) static let loaded: Result<(UnsafePointer<OrtApi>, OpaquePointer), PiperModel.Failure> = {
        var reasons: [String] = []
        for path in candidates {
            var error: UnsafePointer<CChar>?
            guard let api = voicecore_ort_api(path, &error) else {
                reasons.append(error.map { String(cString: $0) } ?? path)
                continue
            }
            var env: OpaquePointer?
            if let status = api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "voice-core", &env) {
                let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "an error with no message"
                api.pointee.ReleaseStatus(status)
                return .failure(.runtime(message))
            }
            guard let env else { return .failure(.noRuntime) }
            return .success((api, env))
        }
        return .failure(.runtimeMissing(reasons.last ?? "nowhere to look"))
    }()

    init(model: URL) throws {
        let (api, env) = try Self.loaded.get()
        self.api = api
        var options: OpaquePointer?
        try Self.check(api, api.pointee.CreateSessionOptions(&options))
        defer { api.pointee.ReleaseSessionOptions(options) }
        var session: OpaquePointer?
        try Self.check(api, api.pointee.CreateSession(env, model.path, options, &session))
        guard let session else { throw PiperModel.Failure.noRuntime }
        self.session = session
        inputNames = try Self.names(api, session, input: true)
        outputNames = try Self.names(api, session, input: false)
    }

    deinit { api.pointee.ReleaseSession(session) }

    private static func check(_ api: UnsafePointer<OrtApi>, _ status: OpaquePointer?) throws {
        guard let status else { return }
        let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "an error with no message"
        api.pointee.ReleaseStatus(status)
        throw PiperModel.Failure.runtime(message)
    }

    private static func names(_ api: UnsafePointer<OrtApi>, _ session: OpaquePointer, input: Bool) throws -> Set<String> {
        var allocator: UnsafeMutablePointer<OrtAllocator>?
        try check(api, api.pointee.GetAllocatorWithDefaultOptions(&allocator))
        var count = 0
        try check(api, input ? api.pointee.SessionGetInputCount(session, &count)
                             : api.pointee.SessionGetOutputCount(session, &count))
        var names: Set<String> = []
        for index in 0..<count {
            var name: UnsafeMutablePointer<CChar>?
            try check(api, input ? api.pointee.SessionGetInputName(session, index, allocator, &name)
                                 : api.pointee.SessionGetOutputName(session, index, allocator, &name))
            if let name {
                names.insert(String(cString: name))
                try check(api, api.pointee.AllocatorFree(allocator, name))
            }
        }
        return names
    }

    func run(_ inputs: [Tensor], outputs wanted: Set<String>) throws -> [String: [Float]] {
        var memory: OpaquePointer?
        try Self.check(api, api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory))
        defer { api.pointee.ReleaseMemoryInfo(memory) }

        // CreateTensorWithDataAsOrtValue does not copy: each buffer lives until Run returns.
        var buffers: [UnsafeMutableRawPointer] = []
        var values: [OpaquePointer?] = []
        defer {
            for value in values { api.pointee.ReleaseValue(value) }
            for buffer in buffers { buffer.deallocate() }
        }
        var names: [String] = []
        for tensor in inputs {
            let (name, bytes, count, kind, shape): (String, UnsafeMutableRawPointer, Int, ONNXTensorElementDataType, [Int])
            switch tensor {
            case .int64(let n, let data, let s):
                let p = UnsafeMutableRawPointer.allocate(byteCount: Swift.max(1, data.count) * 8, alignment: 8)
                data.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
                (name, bytes, count, kind, shape) = (n, p, data.count * 8, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, s)
            case .float(let n, let data, let s):
                let p = UnsafeMutableRawPointer.allocate(byteCount: Swift.max(1, data.count) * 4, alignment: 8)
                data.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
                (name, bytes, count, kind, shape) = (n, p, data.count * 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, s)
            }
            buffers.append(bytes)
            var value: OpaquePointer?
            let dims = shape.map { Int64($0) }
            try Self.check(api, api.pointee.CreateTensorWithDataAsOrtValue(memory, bytes, count, dims, dims.count, kind, &value))
            values.append(value)
            names.append(name)
        }

        let outputNames = Array(wanted)
        var outputs = [OpaquePointer?](repeating: nil, count: outputNames.count)
        defer { for value in outputs { api.pointee.ReleaseValue(value) } }
        try withCStrings(names) { inputPointers in
            try withCStrings(outputNames) { outputPointers in
                try values.withUnsafeBufferPointer { inputValues in
                    try Self.check(api, api.pointee.Run(session, nil, inputPointers, inputValues.baseAddress, values.count,
                                                        outputPointers, outputNames.count, &outputs))
                }
            }
        }

        var result: [String: [Float]] = [:]
        for (name, value) in zip(outputNames, outputs) {
            guard let value else { continue }
            var info: OpaquePointer?
            try Self.check(api, api.pointee.GetTensorTypeAndShape(value, &info))
            var count = 0
            try Self.check(api, api.pointee.GetTensorShapeElementCount(info, &count))
            api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            var data: UnsafeMutableRawPointer?
            try Self.check(api, api.pointee.GetTensorMutableData(value, &data))
            guard let data else { continue }
            result[name] = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
        }
        return result
    }
}

/// C strings for the duration of `body`, as ONNX Runtime's name arrays.
private func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>) throws -> R) rethrows -> R {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    let pointers = copies.map { UnsafePointer($0) }
    return try pointers.withUnsafeBufferPointer { try body($0.baseAddress!) }
}
#endif
