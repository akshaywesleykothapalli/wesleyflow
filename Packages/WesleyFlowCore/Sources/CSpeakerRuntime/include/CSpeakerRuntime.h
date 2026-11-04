#include <stdint.h>
typedef struct WFSpeaker WFSpeaker;
WFSpeaker *WFSpeakerOpen(const char *library, const char *model, int32_t dimension);
int WFSpeakerEmbed(WFSpeaker *, const float *, int32_t count, float *, int32_t dimension);
void WFSpeakerClose(WFSpeaker *);
