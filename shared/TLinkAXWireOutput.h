#pragma once
#include <stddef.h>

namespace TLinkAXWireOutput {
static const size_t MaxSuccessWireBytes = 1024 * 1024;

// Successful UI replies are "0;;" + unwrapped base64(JSON) + CRLF.
inline bool SuccessSize(size_t jsonBytes, size_t &wireBytes) {
    const size_t groups = jsonBytes / 3 + (jsonBytes % 3 != 0);
    if (groups > (MaxSuccessWireBytes - 5) / 4) return false;
    wireBytes = 5 + 4 * groups;
    return true;
}
}
