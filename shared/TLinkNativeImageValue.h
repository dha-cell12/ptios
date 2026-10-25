#ifndef TLINK_NATIVE_IMAGE_VALUE_H
#define TLINK_NATIVE_IMAGE_VALUE_H
#include <cstdint>
// Copied publication metadata; payload ownership remains in the image store.
struct TLinkNativeImageValue {
    uint32_t id=0;
    int width=0,height=0;
};
#endif
