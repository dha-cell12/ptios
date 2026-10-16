#include "../shared/TLinkPlaybackState.h"
#include "../shared/TLinkRawPlayback.h"
#include <cassert>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>
#include <string>
#include <limits>
#include <initializer_list>

static FILE *fileWith(const std::string &text) {
    FILE *file = nullptr;
#ifdef _WIN32
    assert(tmpfile_s(&file) == 0);
#else
    file = tmpfile();
#endif
    assert(file && fwrite(text.data(), 1, text.size(), file) == text.size());
    rewind(file); return file;
}
static void records() {
    int calls = 0, waits = 0;
    bool stop = false;
    auto stopped = [&] { return stop; };
    auto execute = [&](uint8_t *, size_t) { ++calls; };
    FILE *file = fileWith("12one\n181000\r\n12two");
    auto result = TLinkRunRaw(file, 2, stopped, [&](uint64_t ns) { assert(ns == 500000); ++waits; return true; }, execute);
    fclose(file);
    assert(result == TLinkRawResult::Finished && calls == 2 && waits == 1);
    file = fileWith("181000\n12never\n"); calls = 0;
    result = TLinkRunRaw(file, 1, stopped, [&](uint64_t) { stop = true; return true; }, execute);
    fclose(file);
    assert(result == TLinkRawResult::Cancelled && calls == 0);
    stop = false;
    file = fileWith("12first\n12never\n");
    result = TLinkRunRaw(file, 1, stopped, [](uint64_t) { return true; }, [&](uint8_t *, size_t) { ++calls; stop = true; });
    fclose(file);
    assert(result == TLinkRawResult::Cancelled && calls == 1);
    stop = false;
    for (const std::string &bad : {std::string("18-1\n"), std::string("18oops\n"), std::string("182147483648\n"),
                                  std::string("180junk\n"), std::string("12") + std::string(254, 'x'),
                                  std::string("12ok\0hidden\n", 12), std::string("x1bad\n")}) {
        calls = 0; file = fileWith(bad);
        result = TLinkRunRaw(file, 1, stopped, [](uint64_t) { return true; }, execute);
        fclose(file); assert(result == TLinkRawResult::InvalidRecord && calls == 0);
    }
    calls = 0; file = fileWith("12" + std::string(253, 'x'));
    result = TLinkRunRaw(file, 1, stopped, [](uint64_t) { return true; }, execute);
    fclose(file); assert(result == TLinkRawResult::Finished && calls == 1);
    std::string bulk;
    for (int i = 0; i < 100000; ++i) bulk += "12x\n";
    calls = 0; file = fileWith(bulk);
    result = TLinkRunRaw(file, 1, stopped, [](uint64_t) { return true; }, execute);
    fclose(file); assert(result == TLinkRawResult::Finished && calls == 100000);
    assert(TLinkRunRaw(nullptr, 1, stopped, [](uint64_t) { return true; }, execute) == TLinkRawResult::ReadError);
    uint64_t ns;
    assert(TLinkPlaybackDelay(0, &ns) && ns == 0);
    assert(TLinkPlaybackDelay(0.25, &ns) && ns == 250000000);
    for (double bad : {-1.0, 1e300, std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()})
        assert(!TLinkPlaybackDelay(bad, &ns));
}
static void touches() {
    TLinkRawTouches touches;
    auto observe = [&](const char *text) { touches.observe(reinterpret_cast<const uint8_t *>(text), strlen(text)); };
    auto point = [&](int type, int finger, int x, int y) {
        char payload[15];
        assert(std::snprintf(payload, sizeof(payload), "1%d%02d%05d%05d", type, finger, x, y) == 14);
        observe(payload);
    };
    point(1, 0, 100, 200);
    point(1, 19, 300, 400);
    point(2, 19, 500, 600);
    point(0, 0, 100, 200);
    observe("bad");
    int ups = 0;
    auto emit = [&](const uint8_t *bytes, size_t length) {
        TLinkTouchPoint points[kTLinkTouchMaxCount]; int count;
        assert(TLinkParseTouchPayload(bytes, length, points, &count) && count == 1);
        assert(points[0].type == 0 && points[0].index == 19 && points[0].x == 50 && points[0].y == 60);
        ++ups; return true;
    };
    assert(!touches.release([](const uint8_t *, size_t) { return false; }));
    assert(touches.release(emit) && ups == 1);
    assert(touches.release(emit) && ups == 1); // Idempotent after successful release.
}
static void lifecycle() {
    TLinkPlaybackState state;
    const auto first = state.reserve();
    assert(first && state.busy() && state.reserve() == 0);
    assert(state.ready(first) && state.enter(first) && state.wait(first));
    assert(state.stop(first) && !state.enter(first) && state.reserve() == 0);
    assert(state.beginFinish(first) && state.reserve() == 0 && !state.stop(first));
    assert(!state.finish(first + 1) && state.finish(first));
    const auto second = state.reserve();
    assert(second > first && !state.enter(first) && !state.beginFinish(first) && !state.finish(first));
    assert(state.ready(second) && state.enter(second));
    assert(state.wait(second) && state.enter(second));
    assert(state.beginFinish(second) && state.finish(second));
    const auto preparing = state.reserve();
    assert(state.stop(preparing) && !state.ready(preparing) && state.reserve() == 0);
    assert(state.beginFinish(preparing) && state.finish(preparing));

    std::mutex owner;
    std::atomic_int completed{0};
    std::vector<std::thread> clients;
    for (int i = 0; i < 8; ++i) clients.emplace_back([&] {
        for (int cycle = 0; cycle < 10000; ++cycle) {
            std::lock_guard<std::mutex> guard(owner);
            auto generation = state.reserve(); assert(generation);
            assert(state.ready(generation) && state.enter(generation) && state.stop(generation));
            assert(state.reserve() == 0 && !state.enter(generation));
            assert(state.beginFinish(generation) && state.reserve() == 0 && state.finish(generation));
            ++completed;
        }
    });
    for (auto &client : clients) client.join();
    assert(completed == 80000 && !state.busy());
}
static void blockedWorker() {
    TLinkPlaybackState state;
    std::mutex mutex;
    std::condition_variable changed;
    std::atomic_bool stop{false};
    bool inTask = false, releaseTask = false, inCleanup = false, releaseCleanup = false;
    auto generation = state.reserve(); assert(state.ready(generation));
    std::thread worker([&] {
        { std::lock_guard<std::mutex> guard(mutex); assert(state.enter(generation)); }
        FILE *file = fileWith("12blocked\n12must-not-run\n");
        int executed = 0;
        auto result = TLinkRunRaw(file, 1, [&] { return stop.load(); }, [](uint64_t) { return true; },
            [&](uint8_t *, size_t) {
                ++executed;
                std::unique_lock<std::mutex> guard(mutex);
                inTask = true; changed.notify_all();
                changed.wait(guard, [&] { return releaseTask; });
            });
        fclose(file); assert(result == TLinkRawResult::Cancelled && executed == 1);
        std::unique_lock<std::mutex> guard(mutex);
        assert(state.beginFinish(generation));
        inCleanup = true; changed.notify_all();
        changed.wait(guard, [&] { return releaseCleanup; });
        assert(state.finish(generation));
    });
    {
        std::unique_lock<std::mutex> guard(mutex);
        changed.wait(guard, [&] { return inTask; });
        stop = true; assert(state.stop(generation));
        assert(state.reserve() == 0); // Stop ACK is not worker completion.
        releaseTask = true; changed.notify_all();
        changed.wait(guard, [&] { return inCleanup; });
        assert(state.reserve() == 0); // Cleanup still owns the session.
        releaseCleanup = true; changed.notify_all();
    }
    worker.join();
    auto next = state.reserve();
    assert(next > generation && !state.enter(generation));
    assert(state.beginFinish(next) && state.finish(next));
}
int main() {
    records(); touches(); lifecycle(); blockedWorker();
    std::puts("RAW playback safety passed: 100k streamed records, cancellable delays, owned-touch cleanup, blocked task/cleanup admission, stale generations and 8 x 10k lifecycle cycles.");
}
