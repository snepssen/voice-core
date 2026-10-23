# espeak-ng 724808c, for Linux

espeak-ng's library and ucd-tools at commit
`724808c5a83f9ef95fdd0db886ba7ba537ff224a` (piper1-gpl's pin), copied
unchanged from `src/libespeak-ng`, `src/ucd-tools/src` and `src/include`,
built by SwiftPM as the `CEspeakNG` target where there is no XCFramework.
Apple platforms keep `Frameworks/CEspeakNG.xcframework`, built from the same
commit and options by `scripts/build-espeak.sh`.

Only the files the library target compiles with every optional feature off
are here; `config.h` is the one CMake writes for those options. The
dictionaries are not built from these sources: the data is
`Sources/VoiceCore/Resources/espeak-ng-data`, byte-identical to what the
voices were trained with.

GPL-3.0-or-later, as espeak-ng is; see `COPYING`.
