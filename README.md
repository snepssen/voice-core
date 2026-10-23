# voice-core

The speech engine every snepssen app shares, from one source:
[Voice Forge](https://github.com/snepssen/voice-forge),
[Gateway Forge](https://github.com/snepssen/gateway-forge) and the
Interpreter ([interpreter-forge](https://github.com/snepssen/interpreter-forge)).

Each of them carried a copy of the same pieces, and the copies drifted: three
espeak-ng builds of one pinned revision, the same 513 files of its data three
times, a phonemizer in three versions, Polyphon in two languages. Now each
depends on this package at a version, and a release here becomes a version
bump in each of them, checked by that app's own tests before it lands.

| | |
|---|---|
| `CEspeakNG` | espeak-ng at piper1-gpl's commit `724808c`, as an XCFramework for macOS, iOS and the simulator (`scripts/build-espeak.sh`), with its data in the package's resources: the revision, options and dictionaries every snepssen voice was trained through |
| `EspeakPhonemizer` | text to IPA clauses. Each app's policy is an option: Gateway Forge's respellings (`I-There`, `REBAL`), and whether an em dash is spaced so espeak sees it |
| `Polyphon` | espeak-ng corrected for the polyglot voice, a port of [voice-polyglot](https://github.com/snepssen/voice-polyglot)'s `polyphon.py` held to it id for id |
| `PiperModel` | a Piper voice's config, its ONNX session and one inference call, with Voice Forge's per-token duration input when the graph has it |

What is shared is mechanism, not taste. How ids are laid out stays in each
app: Gateway Forge's two trailing pads, Voice Forge's token layout and directed
pauses, the polyglot voice's one run per sentence. A change here must leave
every app's output as it was. The tests hold it to that: Gateway Forge's 481 inference calls phoneme for phoneme and id for id, English phonemes word
for word as Voice Forge's own build gave them, Polyphon id for id against the
Python, respellings and em dashes as options.

No voice is in here. Voices are released by the repositories that train them
([voice-polyglot's releases](https://github.com/snepssen/voice-polyglot/releases))
and fetched by the apps that speak them.

## Use

```swift
.package(url: "https://github.com/snepssen/voice-core", from: "1.0.0"),
// …
.product(name: "VoiceCore", package: "voice-core"),
```

```swift
let model = try PiperModel(model: voiceURL)
let espeak = try EspeakPhonemizer(dataDirectory: EspeakData.directory!, voice: model.config.espeak.voice)
let ids = model.ids(try espeak.phonemize("Build the pattern.", dropFinalStop: true))
let audio = try model.infer(ids, noiseScale: 0.667, lengthScale: 1, noiseW: 0.8).samples
```

## Release

From GitHub: Actions → **release** → run, with a version. The tests run on
macOS; if they pass, the version is tagged. Each app's own daily
**dependencies** workflow (site-core's `update-dependency.yml`, which every
workshop -core shares) then moves it to the new version after its own checks
pass, and pushes; start one by hand from that app's Actions tab to have it at
once.

From a Mac with the apps checked out beside this one:

    scripts/release.sh 1.1.0

(site-core's `workshop release`, so site-core has to be checked out beside
this one too) runs the tests, tags and pushes the version, then, in each app
that `ecosystem.json` says uses voice-core and that is checked out beside this
one, updates the dependency, runs that app's checks and commits and
pushes the bump if they pass. A bump that fails its app's checks is left
uncommitted and reported.

GPL-3.0, as espeak-ng and Piper are.
