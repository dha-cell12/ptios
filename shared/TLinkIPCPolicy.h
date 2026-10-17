#ifndef TLINK_IPC_POLICY_H
#define TLINK_IPC_POLICY_H
#include <cstddef>
#include <cstdint>
#include <cstring>
static const int TLinkIPCNoReplyMessage = 2;
inline bool TLinkIPCNoReplyTouch(int message, const uint8_t *bytes, size_t length) {
    return message == TLinkIPCNoReplyMessage && bytes && length >= 8 && std::memcmp(bytes, "TASK::10", 8) == 0;
}
#endif
