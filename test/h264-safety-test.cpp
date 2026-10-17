#include "../shared/TLinkH264Timing.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>
#ifndef _WIN32
#include <arpa/inet.h>
#endif
class TLinkH264Socket {
public:
    std::vector<uint8_t> bytes;
    std::vector<size_t> writes;
    bool fail = false;
    bool send(const uint8_t *p, size_t n) {
        writes.push_back(n); if (fail) return false;
        bytes.insert(bytes.end(), p, p + n); return true;
    }
};
// The Windows-only fixture fallback avoids a Winsock link dependency.
// POSIX hosts use the same SDK conversion as the production writer.
#ifdef _WIN32
static uint32_t htonl(uint32_t x) { return (x >> 24) | ((x >> 8) & 0xff00U) | ((x << 8) & 0xff0000U) | (x << 24); }
#endif
// Only socket close/shutdown are doubled for the production slot-release helper.
static std::vector<int> closedSockets, shutdownSockets;
static int fixtureClose(int fd) { closedSockets.push_back(fd); return 0; }
static int fixtureShutdown(int fd, int) { shutdownSockets.push_back(fd); return 0; }
#ifdef _WIN32
static const int SHUT_RDWR = 2;
#endif
#define close fixtureClose
#define shutdown fixtureShutdown
namespace root {
static uint64_t zx_now_us() { return 1234567; }
#include "RootActiveUnderTest.inc"
#include "RootReleaseUnderTest.inc"
#include "RootSendUnderTest.inc"
#include "RootEndianUnderTest.inc"
#include "RootRawUnderTest.inc"
#include "RootTSUnderTest.inc"
}
namespace troll {
static uint64_t zx_now_us() { return 1234567; }
#include "TrollActiveUnderTest.inc"
#include "TrollReleaseUnderTest.inc"
#include "TrollSendUnderTest.inc"
#include "TrollEndianUnderTest.inc"
#include "TrollRawUnderTest.inc"
#include "TrollTSUnderTest.inc"
}
#undef close
#undef shutdown
static std::vector<uint8_t> legacy;
static bool legacySendAll(int, const uint8_t *bytes, size_t n) { legacy.insert(legacy.end(), bytes, bytes + n); return true; }
#include "h264-legacy-ts.inc"
int main() {
    // A stale release must close its own socket without clearing a new viewer.
    std::atomic_store(&root::gActiveClientFd, 42);
    root::zx_releaseStreamClient(42); assert(std::atomic_load(&root::gActiveClientFd) == -1);
    std::atomic_store(&root::gActiveClientFd, 43);
    root::zx_releaseStreamClient(42); assert(std::atomic_load(&root::gActiveClientFd) == 43);
    std::atomic_store(&troll::gActiveClientFd, 44);
    troll::zx_releaseStreamClient(44); assert(std::atomic_load(&troll::gActiveClientFd) == -1);
    std::atomic_store(&troll::gActiveClientFd, 45);
    troll::zx_releaseStreamClient(44); assert(std::atomic_load(&troll::gActiveClientFd) == 45);
    assert(closedSockets == std::vector<int>({42, 42, 44, 44}) && shutdownSockets == closedSockets);

    TLinkH264SendWindow window(10, 30); uint64_t now = 0; window.begin(now);
    const uint8_t input[] = {1,2,3,4,5,6,7}; std::vector<uint8_t> received; unsigned calls = 0;
    bool ok = TLinkH264Send(window, input, sizeof(input), [&] { return now; },
        [&](const uint8_t *p, size_t n) -> long long { if (++calls % 2) return -2; size_t count = std::min(size_t(2), n); received.insert(received.end(), p, p + count); return static_cast<long long>(count); },
        [&](uint64_t wait) { assert(wait <= 10); now += 2; return true; });
    assert(ok && received == std::vector<uint8_t>(input, input + sizeof(input)));
    window.begin(0); now = 0;
    assert(!TLinkH264Send(window, input, sizeof(input), [&] { return now; }, [](const uint8_t *, size_t) -> long long { return -2; }, [&](uint64_t wait) { now += wait; return true; }));
    assert(now == 10);
    window.begin(0); now = 0;
    // Separate calls share an access-unit ceiling: progress must not extend it forever.
    for (unsigned n = 0; n < 4; ++n) {
        now += 8;
        bool sent = TLinkH264Send(window, input, 1, [&] { return now; }, [](const uint8_t *, size_t) -> long long { return 1; }, [](uint64_t) { return true; });
        assert(sent == (n < 3));
    }
    window.begin(0); now = 0;
    assert(!TLinkH264Send(window, input, 1, [&] { return now; }, [](const uint8_t *, size_t) -> long long { return 0; }, [](uint64_t) { return true; }));
    assert(!TLinkH264Send(window, input, 1, [&] { return now; }, [](const uint8_t *, size_t) -> long long { return 2; }, [](uint64_t) { return true; }));
    TLinkH264Pacer pacer(0);
    assert(pacer.advance(20000000, 10) == 80000000 && pacer.next() == 100000000);
    assert(pacer.advance(120000000, 10) == 80000000 && pacer.next() == 200000000);
    assert(pacer.advance(550000000, 10) == 50000000 && pacer.next() == 600000000);
    assert(pacer.advance(650000000, 20) == 0);
    assert(pacer.advance(660000000, 20) == 40000000);
    TLinkH264Pacer sustained(0);
    const uint64_t period = 1000000000ULL / 30;
    for (uint64_t n = 0; n < 10000; ++n) {
        const uint64_t start = sustained.next();
        const uint64_t work = n % 100 ? 9000000 : period * 4 + period / 2;
        const uint64_t delay = sustained.advance(start + work, 30);
        assert(delay <= period && sustained.next() % period == 0);
        assert(sustained.next() >= start + work);
    }
    TLinkH264Pacer invalidFPS(0); assert(invalidFPS.advance(1, 0) > 0);
    assert(invalidFPS.advance(1000000001, UINT32_MAX) < 1000000000ULL);
    std::vector<uint8_t> payload(50000);
    for (size_t n = 0; n < payload.size(); ++n) payload[n] = static_cast<uint8_t>(n * 37);
    size_t oldCalls = 0, newCalls = 0;
    for (unsigned test = 0; test < 3000; ++test) {
        size_t length = (test * 313U) % payload.size(); uint8_t a = static_cast<uint8_t>(test & 15), b = a, c = a;
        TLinkH264Socket r, t; legacy.clear(); const bool start = (test & 1) != 0, pcr = (test & 2) != 0;
        assert(legacyWriteTSPackets(0, 0x101, payload.data(), length, start, pcr, 0x1abcdef01ULL, &a));
        assert(root::writeTSPackets(r, 0x101, payload.data(), length, start, pcr, 0x1abcdef01ULL, &b));
        assert(troll::writeTSPackets(t, 0x101, payload.data(), length, start, pcr, 0x1abcdef01ULL, &c));
        assert(a == b && b == c && r.bytes == legacy && t.bytes == legacy);
        assert(r.writes == t.writes && r.writes.size() == (legacy.size() / 188 + 63) / 64);
        for (size_t n : r.writes) assert(n <= 64 * 188 && n % 188 == 0);
        oldCalls += legacy.size() / 188; newCalls += r.writes.size();
    }
    TLinkH264Socket r, t;
    assert(root::writeRawAnnexBFrame(r, input, sizeof(input), true, 42, 100, 200, 300));
    assert(troll::writeRawAnnexBFrame(t, input, sizeof(input), true, 42, 100, 200, 300));
    assert(r.bytes == t.bytes && r.bytes.size() == 52 + sizeof(input));
    assert(memcmp(r.bytes.data(), "ZXH2", 4) == 0 && r.bytes[4] == 1 && r.bytes[11] == 42 && r.bytes[51] == 7);
    TLinkH264Socket failed; failed.fail = true; uint8_t cc = 0;
    assert(!root::writeTSPackets(failed, 0x101, payload.data(), payload.size(), true, true, 0, &cc));
    assert(!troll::writeRawAnnexBFrame(failed, input, sizeof(input), false, 0, 0, 0, 0));
    printf("H264 core passed: production active-slot ownership, access-unit deadlines, exact writes, absolute pacing, 3000 production TS golden cases (root/TrollStore), raw ZXH2; batch calls %zu vs %zu legacy packets.\n", newCalls, oldCalls);
}
