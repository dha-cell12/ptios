#ifndef TLINK_RAW_PLAYBACK_H
#define TLINK_RAW_PLAYBACK_H
#include "TLinkTouchPayload.h"
#include <cmath>
#include <climits>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cerrno>

static inline bool TLinkPlaybackDelay(double seconds, uint64_t *ns) {
    if (!ns || !std::isfinite(seconds) || seconds < 0) return false;
    const long double value = static_cast<long double>(seconds) * 1000000000.0L;
    if (value >= static_cast<long double>(INT64_MAX)) return false;
    *ns = static_cast<uint64_t>(value);
    return true;
}

enum class TLinkRawResult { Finished, Cancelled, ReadError, InvalidRecord };
// Bounded streaming reader: do not execute fragments of an overlong line or embedded NUL.
// Buffered fread avoids a lock-taking stdio call for every input byte. No NSString per delay.
template <typename Stop, typename Wait, typename Execute>
TLinkRawResult TLinkRunRaw(FILE *file, double speed, Stop stopped, Wait wait, Execute execute) {
    if (!file) return TLinkRawResult::ReadError;
    if (!std::isfinite(speed) || speed <= 0) speed = 1;
    char input[4096], line[256];
    size_t cursor = 0, available = 0;
    bool eof = false;
    while (!stopped()) {
        size_t length = 0;
        for (;;) {
            if (cursor == available) {
                available = fread(input, 1, sizeof(input), file); cursor = 0;
                if (available == 0) {
                    if (ferror(file)) return TLinkRawResult::ReadError;
                    eof = true; break;
                }
            }
            const char byte = input[cursor++];
            if (byte == '\0' || length == sizeof(line) - 1) return TLinkRawResult::InvalidRecord;
            line[length++] = byte;
            if (byte == '\n') break;
        }
        if (stopped()) return TLinkRawResult::Cancelled;
        if (length == 0 && eof) return TLinkRawResult::Finished;
        line[length] = '\0';
        if ((length == 1 && line[0] == '\n') || (length == 2 && line[0] == '\r' && line[1] == '\n')) continue;
        if (length < 2 || line[0] < '0' || line[0] > '9' || line[1] < '0' || line[1] > '9') return TLinkRawResult::InvalidRecord;
        if (line[0] == '1' && line[1] == '8') {
            char *end = nullptr;
            errno = 0;
            const long long micros = strtoll(line + 2, &end, 10);
            if (end == line + 2 || errno == ERANGE || micros < 0 || micros > INT_MAX) return TLinkRawResult::InvalidRecord;
            while (*end == '\r' || *end == '\n' || *end == ' ' || *end == '\t') ++end;
            if (*end) return TLinkRawResult::InvalidRecord;
            const long double scaled = static_cast<long double>(micros) / speed;
            // Match legacy truncation to whole microseconds, but reject overflow before casting.
            if (scaled >= static_cast<long double>(INT64_MAX) / 1000) return TLinkRawResult::InvalidRecord;
            const uint64_t ns = static_cast<uint64_t>(scaled) * 1000;
            if (!wait(ns) || stopped()) return TLinkRawResult::Cancelled;
        } else {
            execute(reinterpret_cast<uint8_t *>(line), length);
        }
        if (eof) return stopped() ? TLinkRawResult::Cancelled : TLinkRawResult::Finished;
    }
    return TLinkRawResult::Cancelled;
}

// Observe only successfully injected RAW touch frames, on the playback worker. Cleanup
// emits UP only for those fingers; it must run before publishing this session idle.
class TLinkRawTouches {
    bool down_[kTLinkTouchMaxFingerCount] = {};
    TLinkTouchPoint points_[kTLinkTouchMaxFingerCount] = {};
public:
    void observe(const uint8_t *payload, size_t length) {
        TLinkTouchPoint points[kTLinkTouchMaxCount]; int count = 0;
        if (!TLinkParseTouchPayload(payload, length, points, &count)) return;
        for (int i = 0; i < count; ++i) {
            const auto &point = points[i];
            down_[point.index] = point.type != 0;
            points_[point.index] = point;
        }
    }
    template <typename Emit> bool release(Emit emit) {
        bool ok = true;
        for (int finger = 0; finger < kTLinkTouchMaxFingerCount; ++finger) {
            if (!down_[finger]) continue;
            char payload[15];
            const int length = std::snprintf(payload, sizeof(payload), "10%02d%05d%05d", finger,
                                             points_[finger].x * 10, points_[finger].y * 10);
            if (length != 14 || !emit(reinterpret_cast<const uint8_t *>(payload), 14)) ok = false;
            else down_[finger] = false;
        }
        return ok;
    }
};
#endif
