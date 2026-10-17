#include "../shared/TLinkEventPollCore.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
#include <memory>
#include <string>
int main() {
    assert(!TLinkEventPollExpired(100, 99, 25));
    assert(!TLinkEventPollExpired(100, 124, 25)); assert(TLinkEventPollExpired(100, 125, 25));
    assert(TLinkEventPollExpired(100, 100, 0));
    std::atomic<int> active{0};
    std::vector<std::shared_ptr<TLinkEventPollLease>> leases;
    for (int i = 0; i < 8; ++i) { leases.push_back(std::make_shared<TLinkEventPollLease>(active)); assert(leases.back()->admitted()); }
    { TLinkEventPollLease busy(active); assert(!busy.admitted() && active == 8); }
    for (auto &lease : leases) lease->cancel(); assert(active == 0);
    { TLinkEventPollLease replacement(active); assert(replacement.admitted()); }
    for (auto &lease : leases) assert(!lease->finish()); assert(active == 0);
    std::atomic<unsigned> maximum{0}; std::vector<std::thread> clients;
    for (int i = 0; i < 8; ++i) clients.emplace_back([&] {
        for (int n = 0; n < 10000; ++n) {
            auto lease = std::make_shared<TLinkEventPollLease>(active);
            if (!lease->admitted()) continue;
            unsigned count = static_cast<unsigned>(active.load()), prev = maximum.load();
            while (count > prev && !maximum.compare_exchange_weak(prev,count)) {}
            if (n % 2) lease->cancel(); else lease->finish();
            lease->cancel();
        }
    });
    for (auto &client : clients) client.join(); assert(active == 0 && maximum <= 8);
    for (unsigned n = 0; n < 200; ++n) {
        auto lease = std::make_shared<TLinkEventPollLease>(active);
        std::thread cancellation([lease] { lease->cancel(); });
        lease->finish(); cancellation.join(); assert(active == 0);
    }
    // Every filtered event is delivered once over all pages; unmatched tails are consumed.
    for (unsigned seed = 0; seed < 3000; ++seed) {
        uint64_t cursor = 0; std::vector<uint64_t> delivered, expected;
        const size_t page = seed % 32 + 1;
        for (uint64_t s = 1; s <= 256; ++s) if ((s * 17 + seed) % 11 < 3) expected.push_back(s);
        for (unsigned turn = 0; turn < 257; ++turn) {
            TLinkEventBatchCursor scan(cursor, page);
            for (uint64_t s = 1; s <= 256; ++s) {
                auto action = scan.scan(s, (s * 17 + seed) % 11 < 3);
                if (action == TLinkEventBatchCursor::Stop) break;
                if (action == TLinkEventBatchCursor::Select) delivered.push_back(s);
            }
            uint64_t next = scan.nextCursor(256); assert(next >= cursor && next <= 256); cursor = next;
            if (!scan.more) break;
        }
        assert(cursor == 256 && delivered == expected);
    }
    assert(TLinkEventTopicValid("*",1) && TLinkEventTopicValid("script.RUN-1_",13));
    for (const auto &topic : {std::string(""),std::string("a*b"),std::string("x y"),std::string(65,'a'),std::string("a\0b",3),std::string("\xc3\xa9",2)})
        assert(!TLinkEventTopicValid(topic.data(),topic.size()));
    puts("Event core passed: monotonic deadlines, immediate cancel/re-admission, 80k concurrent lifecycles/200 finish-cancel races, 3000 filtered pagination cases and bounded ASCII topics.");
}
