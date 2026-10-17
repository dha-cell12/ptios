#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <vector>
#include <functional>
#include <cassert>
#include <cstdio>
#include "../shared/TLinkLicenseHotState.h"
#include "../shared/TLinkLicenseVerifier.h"
static std::atomic<uint64_t> clockOffset{0}, fixtureGeneration{1}, frozenNow{0};
static std::atomic<unsigned> statusCalls{0}, statusActive{0}, statusMaximum{0};
static std::atomic<bool> blockNext{false};
static std::mutex providerLock;
static NSDictionary *providerStatus;
static dispatch_semaphore_t entered, releaseWorker;
static void (^notification)(int);
static dispatch_queue_t notificationQueue;
static uint64_t FixtureNow() { uint64_t frozen = frozenNow.load(); return frozen ? frozen : TLinkLicenseHotNowNs() + clockOffset.load(); }
static int FixtureRegisterNotification(const char *, int *token, dispatch_queue_t queue, void (^handler)(int)) {
    *token = 42; notification = [handler copy]; notificationQueue = queue; return 0;
}
uint64_t TLinkLicenseGeneration(void) { return fixtureGeneration.load(); }
NSDictionary *TLinkLicenseStatusDictionary(void) {
    unsigned active = statusActive.fetch_add(1) + 1;
    unsigned maximum = statusMaximum.load();
    while (active > maximum && !statusMaximum.compare_exchange_weak(maximum, active)) {}
    statusCalls.fetch_add(1);
    NSDictionary *result;
    { std::lock_guard<std::mutex> lock(providerLock); result = [providerStatus copy]; }
    if (blockNext.exchange(false)) {
        dispatch_semaphore_signal(entered);
        assert(dispatch_semaphore_wait(releaseWorker, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
    }
    statusActive.fetch_sub(1); return result;
}
#include "LicenseHotUnderTest.inc"
static void waitFor(std::function<bool()> predicate) {
    uint64_t until = TLinkLicenseHotNowNs() + 5000000000ULL;
    while (!predicate()) { assert(TLinkLicenseHotNowNs() < until); std::this_thread::sleep_for(std::chrono::milliseconds(2)); }
}
static NSDictionary *lease(NSArray *features, BOOL enforced = YES, BOOL expired = NO) {
    return @{@"enforcement_enabled": @(enforced), @"licensed": @YES, @"features": features,
        @"offline_until": @(NSDate.date.timeIntervalSince1970 + (expired ? -1 : 3600)), @"license_expires_at": @0,
        @"state": @"valid", @"error": @"", @"license_generation": @(fixtureGeneration.load())};
}
static void setStatus(NSDictionary *status) { std::lock_guard<std::mutex> lock(providerLock); providerStatus = status; }
static void startBlock() {
    entered = dispatch_semaphore_create(0); releaseWorker = dispatch_semaphore_create(0); blockNext.store(true);
}
static void awaitBlock() { assert(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0); }
int main() {
    @autoreleasepool {
        setStatus(lease(@[@"all"]));
        assert(TLinkLicenseFeatureAllowed(@"script", NULL)); assert(statusCalls.load() == 1);
        fputs("License runtime: blocked refresh leaves hot snapshot and generation probes independent\n", stderr);
        startBlock(); clockOffset.fetch_add(4000000000ULL);
        (void)TLinkLicenseCachedStatusDictionary(); awaitBlock();
        waitFor([] { std::lock_guard<std::mutex> lock(sTLinkLicenseSnapshotLock); return sTLinkLicenseHotState.usable(FixtureNow()); });
        unsigned calls = statusCalls.load(); frozenNow.store(FixtureNow());
        for (unsigned n = 0; n < 20000; ++n) assert(TLinkLicenseFeatureAllowed(@"script", NULL));
        assert(statusCalls.load() == calls && statusMaximum.load() == 1); frozenNow.store(0);
        clockOffset.fetch_add(1100000000ULL);
        assert(![TLinkLicenseCachedStatusDictionary()[@"licensed"] boolValue]);
        fputs("License runtime: notification/generation discard a late old result\n", stderr);
        fixtureGeneration.store(2); setStatus(lease(@[@"automation"]));
        dispatch_sync(notificationQueue, ^{ notification(42); });
        assert(![TLinkLicenseCachedStatusDictionary()[@"licensed"] boolValue]);
        dispatch_semaphore_signal(releaseWorker);
        waitFor([] { return [TLinkLicenseCachedStatusDictionary()[@"features"] isEqual:@[@"automation"]]; });
        assert(!TLinkLicenseFeatureAllowed(@"script", NULL)); assert(TLinkLicenseFeatureAllowed(@"automation", NULL));
        fputs("License runtime: cold waiter admission and single-flight recovery\n", stderr);
        setStatus(lease(@[@"all"])); startBlock(); TLinkLicenseInvalidateCache(); awaitBlock();
        std::atomic<unsigned> arrived{0}, finished{0}, allowed{0}, denied{0};
        std::vector<std::thread> clients;
        for (unsigned n = 0; n < 20; ++n) clients.emplace_back([&] { @autoreleasepool {
            arrived.fetch_add(1);
            if (TLinkLicenseFeatureAllowed(@"script", NULL)) allowed.fetch_add(1); else denied.fetch_add(1);
            finished.fetch_add(1);
        } });
        waitFor([&] { std::lock_guard<std::mutex> lock(sTLinkLicenseSnapshotLock);
            return arrived.load() == 20 && sTLinkLicenseColdWaiters == 16 && finished.load() == 4; });
        assert(statusMaximum.load() == 1); dispatch_semaphore_signal(releaseWorker);
        for (auto &client : clients) client.join();
        assert(allowed.load() == 16 && denied.load() == 4);
        fputs("License runtime: signed status generation must match the observed generation\n", stderr);
        NSMutableDictionary *mismatched = [lease(@[@"all"]) mutableCopy]; mismatched[@"license_generation"] = @99;
        setStatus(mismatched); uint64_t completed = sTLinkLicenseFeatureCacheMissCount.load(); TLinkLicenseInvalidateCache();
        waitFor([&] { return sTLinkLicenseFeatureCacheMissCount.load() > completed; });
        assert(![TLinkLicenseCachedStatusDictionary()[@"licensed"] boolValue]);
        fputs("License runtime: expiry, observe policy, idle disarm and resume\n", stderr);
        setStatus(lease(@[@"all"], YES, YES)); TLinkLicenseInvalidateCache();
        waitFor([] { return [TLinkLicenseCachedStatusDictionary()[@"state"] isEqual:@"expired"]; });
        assert(!TLinkLicenseFeatureAllowed(@"script", NULL));
        setStatus(lease(@[], NO)); TLinkLicenseInvalidateCache();
        waitFor([] { return ![TLinkLicenseCachedStatusDictionary()[@"enforcement_enabled"] boolValue]; });
        assert(TLinkLicenseFeatureAllowed(@"script", NULL));
        clockOffset.fetch_add(11000000000ULL);
        waitFor([] { std::lock_guard<std::mutex> lock(sTLinkLicenseSnapshotLock); return !sTLinkLicenseProbeArmed; });
        uint64_t polls = sTLinkLicenseGenerationPollCount.load(); std::this_thread::sleep_for(std::chrono::milliseconds(350));
        assert(sTLinkLicenseGenerationPollCount.load() == polls);
        assert(TLinkLicenseFeatureAllowed(@"script", NULL));
        assert([TLinkLicensePerformanceDictionary()[@"feature_check_count"] unsignedLongLongValue] >= 20000);
        // Drain process-lifetime work before C++ fixture globals are destroyed.
        dispatch_sync(sTLinkLicenseProbeQueue, ^{ dispatch_source_cancel(sTLinkLicenseProbeTimer); });
        dispatch_sync(sTLinkLicenseRefreshQueue, ^{});
        puts("License Foundation passed: actual snapshot adapter, blocked refresh, 20k hot reads, generation/notification races, 16 cold waiters, expiry/observe and idle timer recovery.");
    }
}
