#include "../shared/TLinkLicenseHotState.h"
#include <cassert>
#include <cstdio>
#include <limits>
#include <mutex>
#include <thread>
#include <vector>
int main() {
    TLinkLicenseHotState state; TLinkLicenseHotState::Ticket ticket, other;
    assert(!state.usable(0)); assert(state.begin(0, ticket)); assert(!state.begin(0, other));
    assert(state.finish(ticket, 1, 1, 100, true));
    assert(state.usable(500000100) && !state.usable(500000101));
    state.observe(1, 3999999999ULL); assert(!state.begin(3999999999ULL, other));
    assert(state.begin(4000000000ULL, other)); assert(!state.begin(4000000001ULL, ticket));
    state.observe(1, 4999999999ULL); assert(state.usable(4999999999ULL) && !state.usable(5000000000ULL));
    state.invalidate(); assert(!state.usable(5000000000ULL));
    assert(!state.finish(other, 1, 1, 5000000000ULL, true)); // invalidation wins over a late job
    assert(!state.begin(5000000001ULL, ticket)); // bounded retry cadence
    assert(state.begin(5250000000ULL, ticket));
    assert(!state.finish(ticket, 1, 2, 5250000001ULL, true)); // generation changed during verification
    assert(state.begin(5500000001ULL, ticket));
    assert(state.finish(ticket, 2, 2, 5500000002ULL, true)); assert(state.usable(5500000002ULL));
    state.observe(3, 5500000003ULL); assert(!state.usable(5500000003ULL));
    assert(state.begin(5500000003ULL, ticket));
    assert(!state.finish(ticket, 3, 3, 10500000003ULL, true)); // slow work cannot gain a fresh 5s TTL
    assert(state.begin(10750000003ULL, ticket));
    assert(!state.finish(ticket, 3, 3, 10750000004ULL, false)); // failed verifier
    assert(!state.usable(10750000004ULL));
    assert(TLinkLicenseSnapshotTimeAllowed(1000, 1000, 2000, 0));
    assert(TLinkLicenseSnapshotTimeAllowed(2000, 1000, 2000, 2000));
    assert(!TLinkLicenseSnapshotTimeAllowed(2001, 1000, 2000, 0));
    assert(!TLinkLicenseSnapshotTimeAllowed(1501, 1000, 2000, 1500));
    assert(!TLinkLicenseSnapshotTimeAllowed(699, 1000, 2000, 0));
    assert(!TLinkLicenseSnapshotTimeAllowed(1000, 1000, 0, 0));
    assert(!TLinkLicenseSnapshotTimeAllowed(1000, 1000, std::numeric_limits<double>::quiet_NaN(), 0));
    assert(!TLinkLicenseSnapshotTimeAllowed(1000, 1000, 2000, std::numeric_limits<double>::infinity()));
    // Serialized readers/invalidation must never resurrect a ticket from an old epoch.
    std::mutex lock; TLinkLicenseHotState concurrent;
    std::vector<std::thread> threads;
    for (unsigned id = 0; id < 8; ++id) threads.emplace_back([&] {
        for (unsigned n = 0; n < 10000; ++n) {
            std::lock_guard<std::mutex> guard(lock);
            TLinkLicenseHotState::Ticket current;
            concurrent.invalidate(); assert(concurrent.begin(0, current));
            concurrent.invalidate(); assert(!concurrent.finish(current, 1, 1, 1, true)); assert(!concurrent.usable(1));
        }
    });
    for (auto &t : threads) t.join(); threads.clear();
    TLinkLicenseAuthorityAdmission admission;
    for (unsigned n = 0; n < 8; ++n) assert(admission.acquire());
    assert(!admission.acquire() && admission.active() == 8);
    for (unsigned n = 0; n < 8; ++n) admission.release();
    std::atomic<unsigned> owners{0}, accepted{0};
    for (unsigned id = 0; id < 12; ++id) threads.emplace_back([&] {
        for (unsigned n = 0; n < 10000; ++n) if (admission.acquire()) {
            assert(owners.fetch_add(1) < 8); accepted.fetch_add(1);
            assert(owners.fetch_sub(1) > 0); admission.release();
        }
    });
    for (auto &t : threads) t.join();
    assert(owners.load() == 0 && admission.active() == 0 && accepted.load() > 0);
    puts("License hot state passed: TTL/probe/refresh boundaries, stale epochs/generations, slow verifier, signed-time limits, 80k invalidation cycles and 120k authority admission attempts.");
}
