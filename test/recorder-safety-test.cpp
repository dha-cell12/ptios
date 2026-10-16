#include "../shared/TLinkRecorder.h"
#include "../shared/TLinkRawPlayback.h"
#include <atomic>
#include <cassert>
#include <string>
#include <thread>
#include <vector>

int main() {
    TLinkRecordEvent event;
    assert(TLinkMakeRecordEvent(1000000, 1, 19, 0.5, 0.5, 20, 40, &event));
    assert(event.x10 == 100 && event.y10 == 200);
    assert(!TLinkMakeRecordEvent(0, 1, 20, 0, 0, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 1, -1, 0, 0, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 3, 0, 0, 0, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 1, 0, 0, 0, 20, 0, &event));
    assert(!TLinkMakeRecordEvent(0, 1, 0, -0.01, 0, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 1, 0, 0, 1.01, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 1, 0, NAN, 0, 20, 40, &event));
    assert(!TLinkMakeRecordEvent(0, 1, 0, 0, 0, INFINITY, 40, &event));
    assert(TLinkMakeRecordEvent(0, 1, 0, 1, 1, 9999.9, 9999.9, &event));
    assert(event.x10 == 99999 && event.y10 == 99999);
    for (int i = 0; i < 1000; ++i) {
        const double fraction = double(i) / 999;
        assert(TLinkMakeRecordEvent(0, 2, 0, fraction, fraction, 1080, 1920, &event));
        const float oldX = static_cast<float>(fraction * 1080 * 10), oldY = static_cast<float>(fraction * 1920 * 10);
        char expected[32]; std::snprintf(expected, sizeof(expected), "%05.0f%05.0f", double(oldX), double(oldY));
        char actual[32]; std::snprintf(actual, sizeof(actual), "%05d%05d", event.x10, event.y10);
        assert(std::strcmp(expected, actual) == 0);
    }
    TLinkRecorderEncoder encoder;
    encoder.reset(0); std::string encoded;
    auto emit = [&](const char *data, size_t size) { encoded.append(data, size); return true; };
    event = {1000000, 1, 19, 100, 200};
    assert(encoder.encode(event, emit));
    assert(encoded == "181000\n1011190010000200\n");
    encoded.clear();
    assert(encoder.encode({999999, 0, 19, 100, 200}, emit)); // clamp a regressing arrival, never unsigned underflow
    assert(encoded == "180\n1010190010000200\n");
    encoded.clear(); encoder.reset(0);
    assert(encoder.encode({(2147483647ULL * 2 + 11) * 1000, 2, 0, 0, 0}, emit));
    assert(encoded == "182147483647\n182147483647\n1811\n1012000000000000\n");

    TLinkRecorderBuffer ring;
    auto generation = ring.reserve(); assert(generation && ring.busy() && !ring.reserve());
    assert(!ring.append(generation, &event, 1));
    assert(ring.activate(generation));
    std::vector<TLinkRecordEvent> full(TLinkRecorderBuffer::Capacity, event);
    assert(ring.append(generation, full.data(), full.size()));
    assert(!ring.append(generation, &event, 1));
    assert(ring.failure() == TLinkRecorderFailure::Overflow && ring.pending() == full.size());
    assert(!ring.finish(generation, false));
    std::vector<TLinkRecordEvent> drained(full.size());
    assert(ring.take(generation, drained.data(), drained.size()) == full.size());
    for (const auto &item : drained) assert(item.finger == 19 && item.timeNs == event.timeNs);
    assert(ring.finish(generation, true) && !ring.busy());
    auto next = ring.reserve(); assert(next > generation && ring.activate(next));
    assert(!ring.append(generation, &event, 1) && !ring.take(generation, &event, 1));
    ring.stop(generation); assert(ring.accepts(next));
    ring.stop(next); assert(ring.finish(next, false));

    // Real production ring/encoder/batching + RAW reader. Slow write callbacks never become a timing baseline.
    constexpr int Records = 100000;
    generation = ring.reserve(); assert(ring.activate(generation));
    encoder.reset(1000000000ULL); TLinkRecorderBytes bytes;
    std::string file; size_t writes = 0;
    auto write = [&](const char *data, size_t length) -> ptrdiff_t {
        ++writes;
        if (writes % 100 == 0) std::this_thread::sleep_for(std::chrono::milliseconds(1));
        file.append(data, length); return static_cast<ptrdiff_t>(length);
    };
    auto drain = [&] {
        TLinkRecordEvent chunk[256]; size_t count;
        while ((count = ring.take(generation, chunk, 256)) != 0)
            for (size_t i = 0; i < count; ++i)
                assert(encoder.encode(chunk[i], [&](const char *data, size_t length) { return bytes.append(data, length, write); }));
        assert(bytes.flush(write));
    };
    for (int i = 0; i < Records; i += 20) {
        TLinkRecordEvent frame[20];
        for (int finger = 0; finger < 20; ++finger)
            frame[finger] = {1000000000ULL + uint64_t(i / 20 + 1) * 250000, (i / 20) % 3, finger, finger * 10, finger * 20};
        assert(ring.append(generation, frame, 20));
        if (ring.pending() >= 256) drain();
    }
    ring.stop(generation); assert(ring.busy()); drain(); assert(ring.finish(generation, false));
    assert(writes < 500); // batches, versus one write per event in the old callback
    FILE *raw = nullptr;
#ifdef _MSC_VER
    assert(tmpfile_s(&raw) == 0);
#else
    raw = std::tmpfile();
#endif
    assert(raw);
    assert(std::fwrite(file.data(), 1, file.size(), raw) == file.size()); std::rewind(raw);
    int seen = 0; uint64_t elapsedNs = 0;
    auto result = TLinkRunRaw(raw, 1, [] { return false; }, [&](uint64_t ns) { elapsedNs += ns; return true; },
        [&](uint8_t *payload, size_t size) {
            assert(size >= 2 && payload[0] == '1' && payload[1] == '0');
            TLinkTouchPoint points[kTLinkTouchMaxCount]; int count = 0;
            assert(TLinkParseTouchPayload(payload + 2, size - 2, points, &count) && count == 1);
            assert(points[0].index == seen % 20 && points[0].type == (seen / 20) % 3);
            assert(points[0].x == seen % 20 && points[0].y == (seen % 20) * 2); ++seen;
        });
    assert(result == TLinkRawResult::Finished && seen == Records && elapsedNs == 1250000000ULL);
    std::fclose(raw);

    std::string partial; int attempts = 0;
    assert(TLinkRecordWriteAll("abcdef", 6, [&](const char *data, size_t length) -> ptrdiff_t {
        if (++attempts == 1) { errno = EINTR; return -1; }
        const size_t amount = std::min(size_t(2), length); partial.append(data, amount); return static_cast<ptrdiff_t>(amount);
    }));
    assert(partial == "abcdef" && attempts == 4);
    assert(!TLinkRecordWriteAll("x", 1, [](const char *, size_t) -> ptrdiff_t { return 0; }));
    assert(!TLinkRecordWriteAll("x", 1, [](const char *, size_t) -> ptrdiff_t { errno = ENOSPC; return -1; }));
    assert(!TLinkRecordWriteAll("x", 1, [](const char *, size_t n) -> ptrdiff_t { return static_cast<ptrdiff_t>(n + 1); }));

    std::atomic_int completed{0}; std::vector<std::thread> clients;
    for (int i = 0; i < 8; ++i) clients.emplace_back([&] {
        for (int j = 0; j < 1000; ++j) {
            uintptr_t own;
            while ((own = ring.reserve()) == 0) std::this_thread::yield();
            assert(ring.activate(own) && ring.append(own, &event, 1));
            ring.stop(own); assert(!ring.accepts(own));
            TLinkRecordEvent last; assert(ring.take(own, &last, 1) == 1 && last.finger == 19);
            assert(ring.finish(own, false)); ++completed;
        }
    });
    for (auto &thread : clients) thread.join();
    assert(completed == 8000 && !ring.busy());
    std::printf("Recorder core passed: 100k records round-trip, %zu batched writes, long-gap timing, overflow/stale generations, partial/EINTR/failing writes and 8 x 1k lifecycles.\n", writes);
}
