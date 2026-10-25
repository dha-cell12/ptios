#ifndef TLINK_NATIVE_FRAME_RELEASE_H
#define TLINK_NATIVE_FRAME_RELEASE_H
#include <cstdint>
#include <string>
struct TLinkNativeFrameReleaseRequest {
    uint32_t frameId=0;
    bool all=false,scoped=false;
    std::string sessionId,runId,runtime;
};
#endif
