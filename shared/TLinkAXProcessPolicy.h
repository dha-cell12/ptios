#pragma once
#include <cstddef>
#include <cstring>

namespace TLinkAXProcessPolicy {
static const size_t MaxTableBytes = 16 * 1024 * 1024;
static const size_t SlackEntries = 64;
inline bool Capacity(size_t reported, size_t rowBytes, size_t &capacity) {
    if (!reported || !rowBytes || rowBytes > MaxTableBytes / SlackEntries) return false;
    const size_t slack = rowBytes * SlackEntries;
    if (reported > MaxTableBytes - slack) return false;
    capacity = reported + slack;
    return true;
}
inline bool Count(size_t returned, size_t capacity, size_t rowBytes, size_t &count) {
    if (!rowBytes || capacity > MaxTableBytes || returned > capacity) return false;
    count = returned / rowBytes; // Preserve ignoring an incomplete trailing row.
    return true;
}
// proc_pidpath returns strlen(buffer), excluding the terminator. Validate the
// consumer buffer before passing it to any unbounded C-string/Foundation API.
inline bool Path(const char *bytes, size_t capacity, int reported) {
    if (!bytes || reported <= 0 || static_cast<size_t>(reported) >= capacity) return false;
    return std::memchr(bytes, 0, static_cast<size_t>(reported) + 1) == bytes + reported;
}
}
