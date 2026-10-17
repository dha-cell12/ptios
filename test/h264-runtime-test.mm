#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/file.h>
#include <atomic>
#include <dispatch/dispatch.h>
#include <thread>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>
#include <functional>
#include "../shared/TLinkH264Socket.h"
#include "../shared/TLinkAdaptiveStreaming.h"
#include "../shared/TLinkEventChannel.h"
static NSString *fixtureRoot;
static std::atomic_bool blockRoot(false);
static dispatch_semaphore_t rootEntered, rootRelease;
NSString *TLinkAdaptiveFixtureRoot(void) {
    if (blockRoot.exchange(false)) { dispatch_semaphore_signal(rootEntered); dispatch_semaphore_wait(rootRelease, DISPATCH_TIME_FOREVER); }
    return fixtureRoot;
}
NSDictionary *TLinkEventChannelPublish(NSString *, NSString *, NSString *, NSDictionary *) { return @{}; }
namespace root {
static const uint16_t kTSPatPid = 0, kTSPmtPid = 0x100, kTSVideoPid = 0x101, kTSProgramNumber = 1;
#include "RootActiveUnderTest.inc"
static uint64_t zx_now_us() { return (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000000.0); }
#include "RootSendUnderTest.inc"
#include "RootEndianUnderTest.inc"
#include "RootRawUnderTest.inc"
#include "RootTSUnderTest.inc"
#include "RootPATUnderTest.inc"
#include "RootTablesUnderTest.inc"
#include "RootReleaseUnderTest.inc"
}
namespace troll {
static const uint16_t kTSPatPid = 0, kTSPmtPid = 0x100, kTSVideoPid = 0x101, kTSProgramNumber = 1;
#include "TrollActiveUnderTest.inc"
static uint64_t zx_now_us() { return (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000000.0); }
#include "TrollSendUnderTest.inc"
#include "TrollEndianUnderTest.inc"
#include "TrollRawUnderTest.inc"
#include "TrollTSUnderTest.inc"
#include "TrollPATUnderTest.inc"
#include "TrollTablesUnderTest.inc"
#include "TrollReleaseUnderTest.inc"
}
static void pairOfSockets(int pair[2]) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    int one = 1, size = 1024;
    assert(setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) == 0);
    assert(setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size)) == 0);
}
static void networkCases() {
    // A full peer times out despite repeated poll/readiness wakes; its viewer slot returns.
    std::vector<uint8_t> payload(1024 * 1024, 0x5a);
    for (unsigned runtime = 0; runtime < 2; ++runtime) {
        int pair[2]; pairOfSockets(pair);
        if (!runtime) { root::setClientSocketOptions(pair[0]); std::atomic_store(&root::gActiveClientFd, pair[0]); }
        else { troll::setClientSocketOptions(pair[0]); std::atomic_store(&troll::gActiveClientFd, pair[0]); }
        TLinkH264Socket writer(pair[0], 30000000, 100000000);
        assert(!writer.send(payload.data(), payload.size()));
        if (!runtime) { root::zx_releaseStreamClient(pair[0]); assert(std::atomic_load(&root::gActiveClientFd) == -1); }
        else { troll::zx_releaseStreamClient(pair[0]); assert(std::atomic_load(&troll::gActiveClientFd) == -1); }
        close(pair[1]);
    }
    int pair[2]; pairOfSockets(pair);
    TLinkH264Socket writer(pair[0]); uint8_t a = 0, b = 0;
    assert(root::sendTables(writer, &a, &b)); uint8_t tables[376];
    assert(recv(pair[1], tables, sizeof(tables), MSG_WAITALL) == (ssize_t)sizeof(tables));
    assert(tables[0] == 0x47 && tables[188] == 0x47 && a == 1 && b == 1);
    TLinkH264Socket writer2(pair[0]); assert(troll::sendTables(writer2, &a, &b));
    assert(recv(pair[1], tables, sizeof(tables), MSG_WAITALL) == (ssize_t)sizeof(tables));
    assert(a == 2 && b == 2);
    auto pat = root::buildPAT(0), pmt = troll::buildPMT(0);
    assert(root::mpegCrc32((const uint8_t *)pat.bytes + 5, 16) == 0);
    assert(troll::mpegCrc32((const uint8_t *)pmt.bytes + 5, 21) == 0);
    // Stream both production packetizers through real nonblocking sends and decode payload.
    std::vector<uint8_t> received;
    std::thread reader([&] { uint8_t bytes[8192]; for (;;) { ssize_t n = recv(pair[1], bytes, sizeof(bytes), 0); if (n <= 0) break; received.insert(received.end(), bytes, bytes + n); } });
    uint8_t cc = 0;
    writer.begin(); assert(root::writeTSPackets(writer, 0x101, payload.data(), payload.size(), true, true, 12345, &cc));
    writer.begin(); assert(troll::writeTSPackets(writer, 0x101, payload.data(), payload.size(), true, true, 12345, &cc));
    shutdown(pair[0], SHUT_WR); reader.join();
    std::vector<uint8_t> decoded;
    for (size_t offset = 0; offset < received.size(); offset += 188) {
        const uint8_t *packet = received.data() + offset; assert(packet[0] == 0x47 && received.size() - offset >= 188);
        size_t start = 4; if (packet[3] & 0x20) start += 1 + packet[4]; assert(start <= 188);
        decoded.insert(decoded.end(), packet + start, packet + 188);
    }
    std::vector<uint8_t> expected = payload; expected.insert(expected.end(), payload.begin(), payload.end()); assert(decoded == expected);
    close(pair[0]); close(pair[1]);
    pairOfSockets(pair); close(pair[1]);
    TLinkH264Socket closed(pair[0]); const uint8_t byte = 0;
    assert(!root::writeRawAnnexBFrame(closed, &byte, 1, true, 1, 1, 2, 3));
    assert(!troll::writeRawAnnexBFrame(closed, &byte, 1, true, 1, 1, 2, 3)); close(pair[0]);
}
static NSDictionary *statusAt(NSInteger port) {
    for (NSDictionary *session in TLinkAdaptiveStreamingStatus(@"rootfull")[@"sessions"])
        if ([session[@"port"] integerValue] == port) return session;
    return @{};
}
static void adaptiveCases() {
    TLinkAdaptiveStreamingSessionStartedForSession(@"rootfull", 7004, @"worker", 480, 270, 20, 1200000, @"old");
    TLinkAdaptiveStreamingSessionStartedForSession(@"rootfull", 7004, @"worker", 480, 270, 20, 1200000, @"current");
    NSDictionary *stale = TLinkAdaptiveStreamingDecisionForSession(@"rootfull", 7004, 20, 12, 1200000, 20, 1200000, @"old");
    assert([stale[@"reason"] isEqual:@"session_changed"]);
    TLinkAdaptiveStreamingSessionEndedForSession(@"rootfull", 7004, @"stale_end", @"old");
    assert([statusAt(7004)[@"active"] boolValue]);
    NSString *feedback = [[NSJSONSerialization dataWithJSONObject:@{@"schema": @"stream_feedback_v1", @"port": @7004, @"stalled": @(true)} options:0 error:NULL] base64EncodedStringWithOptions:0];
    NSString *error = nil; assert([TLinkAdaptiveStreamingSubmitFeedback(@"rootfull", feedback, &error)[@"state"] isEqual:@"accepted"] && !error);
    NSDictionary *decision = TLinkAdaptiveStreamingDecisionForSession(@"rootfull", 7004, 20, 12, 1200000, 20, 1200000, @"current");
    assert([decision[@"target_fps"] intValue] == 14 && [decision[@"level"] intValue] == 1);
    // One blocked background decision cannot block reads or queue work for a replacement session.
    dispatch_semaphore_t started = dispatch_semaphore_create(0), finish = dispatch_semaphore_create(0), returned = dispatch_semaphore_create(0);
    TLinkAdaptiveStreamingSampler *sampler = [[TLinkAdaptiveStreamingSampler alloc] initWithFPS:20 minimumFPS:12 bitrate:1200000 decision:^{
        dispatch_semaphore_signal(started); dispatch_semaphore_wait(finish, DISPATCH_TIME_FOREVER); dispatch_semaphore_signal(returned);
        return @{@"target_fps": @15, @"target_bitrate": @800000};
    }];
    int fps = 0, bitrate = 0; [sampler readTargetFPS:&fps bitrate:&bitrate]; assert(fps == 20);
    assert(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    for (int n = 0; n < 10000; ++n) [sampler readTargetFPS:&fps bitrate:&bitrate];
    std::this_thread::sleep_for(std::chrono::milliseconds(3100));
    [sampler readTargetFPS:&fps bitrate:&bitrate]; assert(fps == 12 && bitrate == 200000);
    [sampler invalidate];
    TLinkAdaptiveStreamingSampler *replacement = [[TLinkAdaptiveStreamingSampler alloc] initWithFPS:30 minimumFPS:18 bitrate:2000000 decision:^{ return @{@"target_fps": @24, @"target_bitrate": @1500000}; }];
    [replacement readTargetFPS:&fps bitrate:&bitrate]; assert(fps == 30); // old global job still blocked
    dispatch_semaphore_signal(finish);
    assert(dispatch_semaphore_wait(returned, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    const uint64_t limit = TLinkH264NowNs() + 5000000000ULL;
    do { [replacement readTargetFPS:&fps bitrate:&bitrate]; if (fps == 24) break; std::this_thread::sleep_for(std::chrono::milliseconds(10)); } while (TLinkH264NowNs() < limit);
    assert(fps == 24 && bitrate == 1500000); [replacement invalidate];
    [sampler readTargetFPS:&fps bitrate:&bitrate]; assert(fps == 12); // no late result on invalidated sampler
    // Hold real adaptive I/O at its root boundary; mailbox insertion stays independent.
    rootEntered = dispatch_semaphore_create(0); rootRelease = dispatch_semaphore_create(0); blockRoot.store(true);
    TLinkAdaptiveStreamingRecordRecoveryAsync(@"rootfull", 7004, @"first", true);
    assert(dispatch_semaphore_wait(rootEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    for (unsigned n = 0; n < 1000; ++n) TLinkAdaptiveStreamingRecordRecoveryAsync(@"rootfull", 7004, @"batched_success", true);
    for (unsigned n = 0; n < 200; ++n) TLinkAdaptiveStreamingRecordRecoveryAsync(@"rootfull", 7004, @"batched_failure", false);
    dispatch_semaphore_signal(rootRelease);
    const uint64_t recoveryLimit = TLinkH264NowNs() + 5000000000ULL;
    NSDictionary *session;
    do {
        session = statusAt(7004);
        if ([session[@"recovery_count"] unsignedLongLongValue] == 1001 && [session[@"recovery_failure_count"] unsignedLongLongValue] == 200) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (TLinkH264NowNs() < recoveryLimit);
    assert([session[@"recovery_count"] unsignedLongLongValue] == 1001 && [session[@"recovery_failure_count"] unsignedLongLongValue] == 200);
    TLinkAdaptiveStreamingSessionEndedForSession(@"rootfull", 7004, @"complete", @"current"); assert(![statusAt(7004)[@"active"] boolValue]);
}
int main(int argc, char **argv) {
    assert(argc == 2);
    @autoreleasepool {
        fixtureRoot = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"adaptive"];
        fputs("H264 runtime: real socket backpressure, tables, packetizers and active-slot cleanup\n", stderr); networkCases();
        fputs("H264 runtime: actual adaptive persistence, stale sessions, nonblocking snapshots and coalesced recovery\n", stderr); adaptiveCases();
        puts("H264 Foundation/socket passed: real nonblocking writes/slot cleanup, PAT/PMT CRC, TS payload round-trip, generation gates, blocked sampler and 1201 counted recoveries.");
    }
}
