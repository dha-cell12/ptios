#ifndef TLINK_NATIVE_FRAME_CAPTURE_H
#define TLINK_NATIVE_FRAME_CAPTURE_H
#include <cstdint>
#include <string>
inline uint64_t TLinkNativeFrameCaptureTTL(uint64_t ttl){return ttl?(ttl>5000?5000:ttl):1000;}
struct TLinkNativeFrameCaptureRequest {
    bool gray=true,bgra=true;
    uint64_t ttlMs=1000;
    std::string sessionId,runId,runtime="legacy";
};
#endif
