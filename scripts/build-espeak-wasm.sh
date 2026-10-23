#!/usr/bin/env bash
# espeak-ng as WebAssembly, for the Electron builds: js/espeak.cjs and
# js/espeak.wasm.
#
# The same sources the Linux build compiles (Sources/CEspeakNGLinux, espeak-ng
# 724808c's library and ucd-tools, with the config.h for every voice's
# options), compiled with emscripten (`brew install emscripten`) instead of
# clang. No data is packed in: espeak reads espeak-ng-data off the real disk
# through NODEFS, so every build reads the same bytes.
#
# Why it exists: the `piper-phonemize` npm package bundles espeak-ng 1.52.0,
# 229 commits before the voices' pin. That one lacks the linking glide
# (U+02B2) 724808c inserts after a close front vowel before another vowel,
# `biːʲ ɪn`, and so feeds a voice phonemes it was not trained on, on about a
# quarter of real lines (gateway-forge measured 26%, voice-forge 28%).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v emcc >/dev/null || { echo "emcc not found: brew install emscripten" >&2; exit 1; }
SRC=Sources/CEspeakNGLinux

# `-include wchar.h` is load-bearing (gateway-forge found it): espeak's
# compat/wctype.h macro-renames iswalnum to ucd_isalnum, and musl, which
# emscripten uses, declares iswalnum in <wchar.h> too; without the real header
# first, the macro rewrites that declaration and it conflicts with ucd's.
emcc js/bridge.c "$SRC"/libespeak-ng/*.c "$SRC"/ucd-tools/*.c \
  -I"$SRC/include" -I"$SRC/ucd-tools" -I"$SRC/libespeak-ng" \
  -include wchar.h -DLIBESPEAK_NG_EXPORT=1 -DPATH_ESPEAK_DATA='"/usr/share/espeak-ng-data"' \
  -O3 -Wno-everything \
  -sMODULARIZE=1 -sEXPORT_ES6=0 -sENVIRONMENT=node \
  -sEXPORTED_FUNCTIONS='["_vc_init","_vc_set_voice","_vc_begin","_vc_next","_vc_version","_malloc","_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["ccall","UTF8ToString","getValue","FS","NODEFS"]' \
  -sALLOW_MEMORY_GROWTH=1 -sFILESYSTEM=1 -lnodefs.js \
  -o js/espeak.cjs
echo "built js/espeak.cjs and js/espeak.wasm ($(wc -c < js/espeak.wasm | tr -d ' ') bytes) from $SRC"
