#include "../shared/TLinkSocketOutput.h"
#include "../shared/TLinkIPCPolicy.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>
int main() {
    const uint8_t touch[] = {'T','A','S','K',':',':','1','0'};
    for (size_t n = 0; n < sizeof(touch); ++n) assert(!TLinkIPCNoReplyTouch(2, touch, n));
    assert(TLinkIPCNoReplyTouch(2, touch, sizeof(touch)));
    assert(!TLinkIPCNoReplyTouch(1, touch, sizeof(touch)));
    assert(!TLinkIPCNoReplyTouch(2, nullptr, 100));
    const uint8_t ack[] = "TASK::61"; assert(!TLinkIPCNoReplyTouch(2, ack, 8));
    size_t total = 0;
    TLinkSocketOutput output;
    std::vector<uint8_t> payload(200000), received;
    for (size_t n = 0; n < payload.size(); ++n) payload[n] = static_cast<uint8_t>(n);
    assert(output.append(payload.data(), payload.size(), 100, total));
    size_t calls = 0;
    // Tiny partial sends and repeated EAGAIN preserve every byte and ordering.
    while (!output.empty()) {
        const size_t before = calls;
        auto result = output.pump(101, total, [&](const uint8_t *p, size_t length) -> long long {
            if (++calls % 3 == 0) return 0;
            const size_t count = std::min(size_t(17), length); received.insert(received.end(), p, p + count); return static_cast<long long>(count);
        });
        assert(calls - before <= 4);
        assert(result != TLinkSocketOutput::Result::Failed && total <= TLinkSocketOutput::ClientLimit);
    }
    assert(received == payload && !total);
    assert(output.append(payload.data(), 10, 100, total));
    assert(output.pump(5099, total, [](const uint8_t *, size_t) -> long long { return 0; }) == TLinkSocketOutput::Result::Pending);
    assert(output.pump(5100, total, [](const uint8_t *, size_t) -> long long { assert(false); return 0; }) == TLinkSocketOutput::Result::Failed);
    output.clear(total); assert(!total);
    // A trickling peer cannot keep a response alive beyond its absolute 30s ceiling.
    assert(output.append(payload.data(), payload.size(), 100, total));
    for (uint64_t now = 100; now < 30100; now += 4000)
        assert(output.pump(now, total, [](const uint8_t *, size_t) -> long long { return 1; }) == TLinkSocketOutput::Result::Pending);
    assert(output.pump(30100, total, [](const uint8_t *, size_t) -> long long { return 1; }) == TLinkSocketOutput::Result::Failed);
    output.clear(total);
    // Retained allocation, including a sent prefix, stays charged until the chunk completes.
    assert(output.append(payload.data(), payload.size(), 0, total));
    assert(output.pump(1, total, [](const uint8_t *, size_t n) -> long long { return static_cast<long long>(n); }) == TLinkSocketOutput::Result::Pending);
    assert(total == payload.size() && output.owned() == payload.size()); output.clear(total);
    std::vector<uint8_t> full(TLinkSocketOutput::ClientLimit, 1);
    TLinkSocketOutput clients[9];
    for (int n = 0; n < 8; ++n) assert(clients[n].append(full.data(), full.size(), 0, total));
    assert(total == TLinkSocketOutput::GlobalLimit);
    assert(!clients[8].append(full.data(), 1, 0, total));
    assert(!clients[0].append(full.data(), 1, 0, total));
    for (auto &client : clients) client.clear(total);
    assert(!total);
    for (int n = 0; n < 128; ++n) assert(output.append(full.data(), 1, 0, total));
    assert(!output.append(full.data(), 1, 0, total)); output.clear(total);
    assert(output.append(full.data(), 1, 0, total));
    assert(output.pump(0, total, [](const uint8_t *, size_t) -> long long { return -1; }) == TLinkSocketOutput::Result::Failed); output.clear(total);
    assert(output.append(full.data(), 1, 0, total));
    assert(output.pump(0, total, [](const uint8_t *, size_t) -> long long { return 2; }) == TLinkSocketOutput::Result::Failed); output.clear(total);
    for (int cycle = 0; cycle < 100000; ++cycle) {
        assert(output.append(payload.data(), 16, 0, total));
        if (cycle % 2) {
            assert(output.pump(1, total, [](const uint8_t *, size_t n) -> long long { return static_cast<long long>(n); }) == TLinkSocketOutput::Result::Empty);
        } else output.clear(total);
        assert(!total && output.empty());
    }
    puts("Socket output passed: exact partial/EAGAIN writes, fairness, no-progress/absolute deadlines, client/global/chunk caps and 100k clean lifecycles.");
}
