#pragma once
#include <stddef.h>
#include <limits>

namespace TLinkAXSnapshotOutput {
static const size_t MaxStringUTF8Bytes = 64 * 1024;

// Preserve the existing conservative escaped-JSON estimate, without overflow.
inline bool AddString(size_t bytes, size_t &rowBytes) {
    if (bytes > MaxStringUTF8Bytes || bytes > (std::numeric_limits<size_t>::max() - rowBytes) / 6) return false;
    rowBytes += 6 * bytes;
    return true;
}

inline bool AppendRow(size_t rowBytes, size_t current, size_t &next, size_t &wireBytes) {
    const size_t maximum = std::numeric_limits<size_t>::max();
    if (rowBytes > maximum - current) return false;
    const size_t total = current + rowBytes;
    const size_t groups = total / 3 + (total % 3 != 0);
    if (groups > (maximum - 32 * 1024) / 4) return false;
    next = total;
    wireBytes = 32 * 1024 + 4 * groups;
    return true;
}
}
