// ONNX Runtime's C API, loaded at run time where the Apple package is not.
//
// voice-core links no ONNX Runtime on Linux. `voicecore_ort_api` opens the
// shared library Microsoft publishes (onnxruntime-linux-*-1.24.2) and returns
// its API table, so `swift build` needs nothing installed and a program that
// never speaks never needs the library at all.
#pragma once
#include "onnxruntime_c_api.h"

// The API table from the library at `path`, or NULL with `error` set to why.
// The library stays loaded for the life of the process.
const OrtApi *voicecore_ort_api(const char *path, const char **error);
