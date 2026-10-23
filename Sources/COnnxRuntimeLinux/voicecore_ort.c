#include "voicecore_ort.h"
#include <dlfcn.h>

const OrtApi *voicecore_ort_api(const char *path, const char **error) {
    void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        *error = dlerror();
        return NULL;
    }
    typedef const OrtApiBase *(*GetApiBase)(void);
    GetApiBase base = (GetApiBase)dlsym(library, "OrtGetApiBase");
    if (!base) {
        *error = "the library has no OrtGetApiBase: not ONNX Runtime";
        return NULL;
    }
    const OrtApi *api = base()->GetApi(ORT_API_VERSION);
    if (!api) *error = "the library is older than ONNX Runtime 1.24, the version voice-core is built against";
    return api;
}
