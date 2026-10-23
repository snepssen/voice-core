#!/usr/bin/env bash
# ONNX Runtime for Linux: Microsoft's published library, the version the Apple
# package resolves to (1.24.2), checked against its SHA-256 and unpacked where
# voice-core's PiperModel looks first. No root: it goes in the user's data
# folder, shared by every snepssen app, the way the models are.
#
#   scripts/fetch-onnxruntime.sh          # fetch if missing, print the path
#   scripts/fetch-onnxruntime.sh --check  # exit 0 if present, 1 if not
#
# Apple platforms need none of this; their runtime comes with the package.
set -euo pipefail
VERSION=1.24.2
case "$(uname -m)" in
  x86_64)        ARCH=x64;     SHA=43725474ba5663642e17684717946693850e2005efbd724ac72da278fead25e6 ;;
  aarch64|arm64) ARCH=aarch64; SHA=6715b3d19965a2a6981e78ed4ba24f17a8c30d2d26420dbed10aac7ceca0085e ;;
  *) echo "no ONNX Runtime $VERSION release for $(uname -m)" >&2; exit 1 ;;
esac
[ "$(uname -s)" = Linux ] || { echo "only Linux needs this; Apple platforms link the runtime" >&2; exit 1; }

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/snepssen/onnxruntime/$VERSION"
LIB="$ROOT/lib/libonnxruntime.so"
if [ "${1:-}" = "--check" ]; then [ -f "$LIB" ]; exit; fi
if [ -f "$LIB" ]; then echo "$LIB"; exit 0; fi

NAME="onnxruntime-linux-$ARCH-$VERSION"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "fetching $NAME.tgz from github.com/microsoft/onnxruntime" >&2
curl -fsSL "https://github.com/microsoft/onnxruntime/releases/download/v$VERSION/$NAME.tgz" -o "$WORK/ort.tgz"
echo "$SHA  $WORK/ort.tgz" | sha256sum -c --quiet - || { echo "checksum mismatch: not installed" >&2; exit 1; }
tar -xzf "$WORK/ort.tgz" -C "$WORK"
mkdir -p "$(dirname "$ROOT")"
rm -rf "$ROOT.partial" && mv "$WORK/$NAME" "$ROOT.partial" && mv "$ROOT.partial" "$ROOT"
echo "$LIB"
