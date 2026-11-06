#pragma once
#include <cstddef>

namespace TLinkAXSelectorPolicy {
static const size_t MaxFieldUTF8Bytes = 65536;
inline bool AdmitUTF16(size_t units) { return units <= MaxFieldUTF8Bytes; }
inline bool AdmitUTF8(size_t bytes) { return bytes <= MaxFieldUTF8Bytes; }
}
