#!/usr/bin/env bash
# ONNX Runtime for Linux: Microsoft's published library, the version the Apple
# package resolves to (1.24.2), taken from their NuGet package (the GitHub
# release it used to come from left with microsoft/onnxruntime in November
# 2026), checked against its SHA-256 and unpacked where
# voice-core's PiperModel looks first. No root: it goes in the user's data
# folder, shared by every snepssen app, the way the models are.
#
#   scripts/fetch-onnxruntime.sh          # fetch if missing, print the path
#   scripts/fetch-onnxruntime.sh --check  # exit 0 if present, 1 if not
#
# Apple platforms need none of this; their runtime comes with the package.
set -euo pipefail
VERSION=1.24.2
# The NuGet package holds every platform's library; this is its SHA-256.
SHA=782564d3d68e87269ea1812cc94710ad06fe014faf093f01a6f89d0bd58719d3
case "$(uname -m)" in
  x86_64)        ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "no ONNX Runtime $VERSION release for $(uname -m)" >&2; exit 1 ;;
esac
[ "$(uname -s)" = Linux ] || { echo "only Linux needs this; Apple platforms link the runtime" >&2; exit 1; }

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/snepssen/onnxruntime/$VERSION"
LIB="$ROOT/lib/libonnxruntime.so"
if [ "${1:-}" = "--check" ]; then [ -f "$LIB" ]; exit; fi
if [ -f "$LIB" ]; then echo "$LIB"; exit 0; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "fetching Microsoft.ML.OnnxRuntime $VERSION from nuget.org (about 125 MB)" >&2
curl -fsSL "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$VERSION/microsoft.ml.onnxruntime.$VERSION.nupkg" -o "$WORK/ort.nupkg"
echo "$SHA  $WORK/ort.nupkg" | sha256sum -c --quiet - || { echo "checksum mismatch: not installed" >&2; exit 1; }
mkdir -p "$WORK/out/lib"
for f in LICENSE ThirdPartyNotices.txt "runtimes/linux-$ARCH/native/libonnxruntime.so"; do
  python3 -c 'import sys, zipfile; sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' \
    "$WORK/ort.nupkg" "$f" > "$WORK/out/$( [ "${f##*.}" = so ] && echo lib/ )$(basename "$f")"
done
mkdir -p "$(dirname "$ROOT")"
rm -rf "$ROOT.partial" && mv "$WORK/out" "$ROOT.partial" && mv "$ROOT.partial" "$ROOT"
echo "$LIB"
