#include "../shared/TLinkSchedulerState.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include <initializer_list>

struct Resource {
    static std::atomic_int live;
    bool cancelled = false;
    Resource() { ++live; }
    ~Resource() { assert(cancelled); --live; }
};
std::atomic_int Resource::live{0};
struct Timer {
    std::shared_ptr<Resource> resource = std::make_shared<Resource>();
    void cancel() { assert(!resource->cancelled); resource->cancelled = true; }
};
using Registry = TLinkSchedulerRegistry<Timer>;
static void intervals() {
    uint64_t ns = 0;
    assert(!TLinkSchedulerInterval(1, true, nullptr));
    for (double bad : {0.0, -1.0, std::numeric_limits<double>::infinity(),
                       std::numeric_limits<double>::quiet_NaN(), 1e300, 1e-12}) {
        assert(!TLinkSchedulerInterval(bad, false, &ns) && ns == 0);
        assert(!TLinkSchedulerInterval(bad, true, &ns) && ns == 0);
    }
    for (double subsecond : {0.001, 0.01, 0.1, 0.999}) {
        assert(!TLinkSchedulerInterval(subsecond, true, &ns));
        assert(TLinkSchedulerInterval(subsecond, false, &ns) && ns > 0);
    }
    assert(TLinkSchedulerInterval(1, true, &ns) && ns == 1000000000);
    assert(TLinkSchedulerLeeway(ns) == 100000000);
    assert(TLinkSchedulerInterval(0.1, false, &ns) && TLinkSchedulerLeeway(ns) == ns / 10);
    assert(TLinkSchedulerInterval(86400, true, &ns) && ns == uint64_t(86400) * 1000000000);
    assert(!TLinkSchedulerInterval(static_cast<double>(INT64_MAX) / 1e9 + 1, false, &ns));
}
static void lifecycle() {
    Registry registry;
    int launches = 0;
    auto launch = [&](const Timer &timer) { assert(timer.resource && !timer.resource->cancelled); ++launches; };
    Timer first;
    auto old = registry.set("same", first, true);
    assert(old && registry.size() == 1);
    assert(registry.fire("same", old, false, launch) == TLinkSchedulerFireResult::Launched);
    assert(registry.fire("same", old, true, launch) == TLinkSchedulerFireResult::Busy && launches == 1);
    Timer second;
    auto replacement = registry.set("same", second, true);
    assert(first.resource->cancelled && !second.resource->cancelled && replacement > old && registry.size() == 1);
    assert(registry.fire("same", old, false, launch) == TLinkSchedulerFireResult::Stale);
    registry.remove("same");
    registry.remove("same"); // Idempotent cancellation.
    assert(second.resource->cancelled && registry.size() == 0);
    assert(registry.fire("same", replacement, false, launch) == TLinkSchedulerFireResult::Stale);
    Timer third;
    auto restarted = registry.set("same", third, true);
    assert(restarted > replacement);
    assert(registry.fire("same", replacement, false, launch) == TLinkSchedulerFireResult::Stale);
    registry.remove("same");
    assert(launches == 1);

    // Consume a one-shot even when admission refuses it, without entering license/config work.
    auto once = registry.set("once", Timer{}, false);
    assert(registry.fire("once", once, true, launch) == TLinkSchedulerFireResult::Busy);
    assert(registry.size() == 0 && launches == 1);
    assert(registry.fire("once", once, false, launch) == TLinkSchedulerFireResult::Stale);
    once = registry.set("once", Timer{}, false);
    uint64_t newOnce = 0;
    registry.fire("once", once, false, [&](const Timer &timer) {
        assert(timer.resource->cancelled); // Removed, but owning local copy remains alive.
        assert(registry.size() == 0);
        newOnce = registry.set("once", Timer{}, true);
    });
    assert(newOnce > once && registry.size() == 1);
    assert(registry.fire("once", once, false, launch) == TLinkSchedulerFireResult::Stale);
    registry.remove("once"); // Old one-shot cleanup cannot erase a reentrant replacement.
}
static void stress() {
    Registry registry;
    std::mutex owner; // Same serialization contract as production's dispatch queue.
    std::vector<std::thread> clients;
    int launches = 0;
    for (int client = 0; client < 8; ++client) {
        clients.emplace_back([&] {
            for (int i = 0; i < 10000; ++i) {
                uint64_t old;
                { std::lock_guard<std::mutex> guard(owner); old = registry.set("shared", Timer{}, true); }
                {
                    std::lock_guard<std::mutex> guard(owner);
                    registry.remove("shared"); // Represents a committed remove ACK.
                    auto stale = registry.fire("shared", old, false, [&](const Timer &) { ++launches; });
                    assert(stale == TLinkSchedulerFireResult::Stale);
                    auto latest = registry.set("shared", Timer{}, true);
                    assert(registry.fire("shared", old, false, [&](const Timer &) { ++launches; }) == TLinkSchedulerFireResult::Stale);
                    registry.fire("shared", latest, false, [&](const Timer &) { ++launches; });
                    registry.remove("shared");
                }
            }
        });
    }
    for (auto &client : clients) client.join();
    assert(launches == 80000 && registry.size() == 0);
}
int main() {
    intervals(); lifecycle(); stress();
    assert(Resource::live == 0);
    std::puts("Scheduler safety passed: interval policy, generation/one-shot/admission checks, 8 clients x 10,000 cycles; zero live timer resources.");
}
