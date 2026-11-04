#include "CSpeakerRuntime.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

/* C API layouts from sherpa-onnx 1.13.8, Apache-2.0.
 * Only the locally packaged framework's exported symbols are used. */
typedef struct { const char *model; int32_t threads, debug; const char *provider; } Config;
struct WFSpeaker {
    void *library;
    const void *context;
    void (*destroy)(const void *);
    int32_t (*dimension)(const void *);
    const void *(*stream)(const void *);
    void (*destroyStream)(const void *);
    void (*accept)(const void *, int32_t, const float *, int32_t);
    void (*finish)(const void *);
    int32_t (*ready)(const void *, const void *);
    const float *(*compute)(const void *, const void *);
    void (*freeVector)(const float *);
};

void WFSpeakerClose(WFSpeaker *speaker) {
    if (!speaker) return;
    if (speaker->context) speaker->destroy(speaker->context);
    if (speaker->library) dlclose(speaker->library);
    free(speaker);
}

WFSpeaker *WFSpeakerOpen(const char *library, const char *model, int32_t dimension) {
    WFSpeaker *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->library = dlopen(library, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
    if (!s->library) goto failure;
    const void *(*create)(const Config *) = dlsym(s->library, "SherpaOnnxCreateSpeakerEmbeddingExtractor");
#define LOAD(field, symbol) if (!(s->field = dlsym(s->library, symbol))) goto failure
    LOAD(destroy, "SherpaOnnxDestroySpeakerEmbeddingExtractor");
    LOAD(dimension, "SherpaOnnxSpeakerEmbeddingExtractorDim");
    LOAD(stream, "SherpaOnnxSpeakerEmbeddingExtractorCreateStream");
    LOAD(destroyStream, "SherpaOnnxDestroyOnlineStream");
    LOAD(accept, "SherpaOnnxOnlineStreamAcceptWaveform");
    LOAD(finish, "SherpaOnnxOnlineStreamInputFinished");
    LOAD(ready, "SherpaOnnxSpeakerEmbeddingExtractorIsReady");
    LOAD(compute, "SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding");
    LOAD(freeVector, "SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding");
#undef LOAD
    if (!create) goto failure;
    Config config = {model, 1, 0, "cpu"};
    s->context = create(&config);
    if (s->context && s->dimension(s->context) == dimension) return s;
failure:
    WFSpeakerClose(s);
    return NULL;
}

int WFSpeakerEmbed(WFSpeaker *s, const float *samples, int32_t count, float *output, int32_t dimension) {
    if (s->dimension(s->context) != dimension) return 0;
    const void *stream = s->stream(s->context);
    if (!stream) return 0;
    s->accept(stream, 16000, samples, count);
    s->finish(stream);
    const float *vector = s->ready(s->context, stream) ? s->compute(s->context, stream) : NULL;
    if (vector) {
        memcpy(output, vector, (size_t)dimension * sizeof(float));
        s->freeVector(vector);
    }
    s->destroyStream(stream);
    return vector != NULL;
}
