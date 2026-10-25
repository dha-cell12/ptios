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
// Numeric capture output; publication ownership is reported separately before formatting.
struct TLinkNativeFrameCaptureValue {
    uint32_t id=0;
    int width=0,height=0,bytesPerRow=0;
    double scale=0,captureMs=0,bgraMs=0,grayMs=0,totalMs=0;
    bool hasBGRA=false,hasGray=false;
    uint64_t capturedAtMs=0;
};
#endif
