#ifndef TLINK_TOUCH_PAYLOAD_H
#define TLINK_TOUCH_PAYLOAD_H

#include <stddef.h>
#include <stdint.h>

// The legacy wire count is one digit; finger IDs still span 0..19.
enum {
    kTLinkTouchDataLength = 13,
    kTLinkTouchMaxCount = 9,
    kTLinkTouchMaxFingerCount = 20,
};

struct TLinkTouchPoint {
    int type;
    int index;
    int x;
    int y;
};

static inline bool TLinkParseTouchPayload(const uint8_t *data, size_t length,
                                         TLinkTouchPoint (&points)[kTLinkTouchMaxCount],
                                         int *touchCount)
{
    if (!touchCount) return false;
    *touchCount = 0;
    if (!data || length < 1 || data[0] < '1' || data[0] > '9') return false;
    const int count = data[0] - '0';
    const size_t required = 1 + (size_t)count * kTLinkTouchDataLength;
    if (length < required || length - required > 2) return false;
    // RAW lines may end in LF, CR or CRLF; no other suffix or embedded NUL is valid.
    if (length == required + 1 && data[required] != '\n' && data[required] != '\r') return false;
    if (length == required + 2 && (data[required] != '\r' || data[required + 1] != '\n')) return false;

    for (int i = 0; i < count; i++) {
        const uint8_t *field = data + 1 + (size_t)i * kTLinkTouchDataLength;
        if (field[0] < '0' || field[0] > '2') return false;
        int values[3] = {0, 0, 0};
        for (int digit = 1; digit < kTLinkTouchDataLength; digit++) {
            if (field[digit] < '0' || field[digit] > '9') return false;
            const int valueIndex = digit < 3 ? 0 : (digit < 8 ? 1 : 2);
            values[valueIndex] = values[valueIndex] * 10 + field[digit] - '0';
        }
        if (values[0] >= kTLinkTouchMaxFingerCount) return false;
        // Preserve the injector's existing integer-pixel truncation of fixed-point coordinates.
        points[i] = {field[0] - '0', values[0], values[1] / 10, values[2] / 10};
    }
    *touchCount = count;
    return true;
}

#endif
