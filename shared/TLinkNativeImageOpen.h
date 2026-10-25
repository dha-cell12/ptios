#ifndef TLINK_NATIVE_IMAGE_OPEN_H
#define TLINK_NATIVE_IMAGE_OPEN_H
#include <cstddef>
#include <string>
// The retained path/owner compatibility tail excludes the five ASCII units in "482;;".
inline bool TLinkNativeImageOpenInputFits(size_t units){return units<=8192-5;}
inline bool TLinkNativeImageOpenBytesFit(size_t bytes){return bytes<=32*1024-5;}
#ifdef __OBJC__
#import <Foundation/Foundation.h>
struct TLinkNativeImageOpenRequest {
    // ARC retains the parsed path without a second UTF-8 decoding step.
    NSString *path=@"";
    std::string sessionId,runId,runtime="legacy";
};
#endif
#endif
