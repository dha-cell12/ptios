#ifndef TLINK_NATIVE_IMAGE_RELEASE_H
#define TLINK_NATIVE_IMAGE_RELEASE_H
#include <cstdint>
#include <string>
struct TLinkNativeImageReleaseRequest {
    uint32_t imageId=0;
    bool all=false,scoped=false;
    std::string sessionId,runId,runtime;
};
#endif
