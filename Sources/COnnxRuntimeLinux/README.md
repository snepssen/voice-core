# ONNX Runtime's C API, for Linux

`include/onnxruntime_c_api.h` and `include/onnxruntime_ep_c_api.h` are ONNX
Runtime 1.24.2's headers, unchanged (MIT, Microsoft; see `LICENSE`): the
version the Apple package resolves to in every snepssen app. The library
itself is not linked. `voicecore_ort.c` opens Microsoft's published
`libonnxruntime.so` at run time, and `PiperModel` looks for it where
`scripts/fetch-onnxruntime.sh` puts it.
