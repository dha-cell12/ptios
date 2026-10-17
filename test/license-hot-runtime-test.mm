#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <atomic>
#include <mutex>
#include <memory>
#include <condition_variable>
#include <thread>
#include <vector>
#include <functional>
#include <cassert>
#include <cstdio>
#include <cstring>
#include "../shared/TLinkLicenseHotState.h"
#include "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkRootfullLicenseBuild.h"
static std::atomic<uint64_t> clockOffset{0}, fixtureGeneration{1}, frozenNow{0};
static std::atomic<unsigned> statusCalls{0}, statusActive{0}, statusMaximum{0};
static std::atomic<bool> blockNext{false};
static std::mutex providerLock;
static std::thread::id fixtureMainThread;
static std::atomic<unsigned> mainGenerationReads{0}, mainStatusReads{0};
static NSDictionary *providerStatus;
static dispatch_semaphore_t entered, releaseWorker;
static void (^notification)(int);
static dispatch_queue_t notificationQueue;
static uint64_t FixtureNow() { uint64_t frozen = frozenNow.load(); return frozen ? frozen : TLinkLicenseHotNowNs() + clockOffset.load(); }
static int FixtureRegisterNotification(const char *, int *token, dispatch_queue_t queue, void (^handler)(int)) {
    *token = 42; notification = [handler copy]; notificationQueue = queue; return 0;
}
uint64_t TLinkLicenseGeneration(void) { if (std::this_thread::get_id() == fixtureMainThread) mainGenerationReads.fetch_add(1); return fixtureGeneration.load(); }
uint64_t TLinkLicenseAdvanceGeneration(void) { uint64_t value = fixtureGeneration.fetch_add(1) + 1; TLinkLicenseInvalidateCache(); return value; }
const char *TLinkRootfullLicenseBuildMode(void) { return "fixture"; }
NSString *TLinkLicenseBuildMode(void) { return @"fixture"; }
NSDictionary *TLinkLicenseStatusDictionary(void) {
    if (std::this_thread::get_id() == fixtureMainThread) mainStatusReads.fetch_add(1);
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
static void TLinkLicenseInvalidateArtifacts(void) {}
static NSDictionary *TLinkLicenseArtifactPerformance(void) { return @{}; }
#include "LicenseHotUnderTest.inc"
static std::atomic<uint64_t> sTLinkRootfullLicenseTask10DropCount{0};
static NSData *zx_dataFromCString(const char *value) { return [[NSString stringWithUTF8String:value] dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *TLinkSuccess(NSString *value) { return [[NSString stringWithFormat:@"0;;%@\r\n", value] dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *TLinkError(NSString *value) { return [[NSString stringWithFormat:@"-1;;%@\r\n", value] dataUsingEncoding:NSUTF8StringEncoding]; }
#include "LicenseDiagnosticsUnderTest.inc"
static NSDictionary *decodeStatus(NSData *wire) {
    NSString *line = [[[NSString alloc] initWithData:wire encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    assert([line hasPrefix:@"0;;"]);
    NSData *json = [[NSData alloc] initWithBase64EncodedString:[line substringFromIndex:3] options:0];
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL]; assert(value); return value;
}

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
        fixtureMainThread = std::this_thread::get_id();
        setStatus(lease(@[@"all"]));
        assert(TLinkLicenseFeatureAllowed(@"script", NULL)); assert(statusCalls.load() == 1);
        auto automation = TLinkLicenseAutomationAuthorizationForOwner(@"raw-1");
        assert(automation(@"raw-1") && !automation(@"raw-2"));
        frozenNow.store(FixtureNow());
        for (unsigned n = 0; n < 20000; ++n) assert(automation(@"raw-1"));
        frozenNow.store(0);
        unsigned freshDiagnostics = statusCalls.load();
        assert([TLinkLicenseDiagnosticStatus(@"cached")[@"diagnostic_freshness"] isEqual:@"cached"]);
        assert(statusCalls.load() == freshDiagnostics);
        (void)TLinkLicenseDiagnosticStatus(@"fresh"); assert(statusCalls.load() == freshDiagnostics + 1);
        fputs("License runtime: blocked refresh leaves hot snapshot and generation probes independent\n", stderr);
        startBlock(); clockOffset.fetch_add(4000000000ULL);
        (void)TLinkLicenseCachedStatusDictionary(); awaitBlock();
        waitFor([] { std::lock_guard<std::mutex> lock(sTLinkLicenseSnapshotLock); return sTLinkLicenseHotState.usable(FixtureNow()); });
        unsigned calls = statusCalls.load(); frozenNow.store(FixtureNow());
        for (unsigned n = 0; n < 20000; ++n) assert(TLinkLicenseFeatureAllowed(@"script", NULL));
        assert(statusCalls.load() == calls && statusMaximum.load() == 1); frozenNow.store(0);
        clockOffset.fetch_add(1100000000ULL);
        assert(![TLinkLicenseCachedStatusDictionary()[@"licensed"] boolValue]);
        assert(!automation(@"raw-1"));
        fputs("License runtime: notification/generation discard a late old result\n", stderr);
        fixtureGeneration.store(2); setStatus(lease(@[@"automation"]));
        dispatch_sync(notificationQueue, ^{ notification(42); });
        assert(![TLinkLicenseCachedStatusDictionary()[@"licensed"] boolValue]);
        assert(!automation(@"raw-1"));
        dispatch_semaphore_signal(releaseWorker);
        waitFor([] { return [TLinkLicenseCachedStatusDictionary()[@"features"] isEqual:@[@"automation"]]; });
        assert(!TLinkLicenseFeatureAllowed(@"script", NULL)); assert(TLinkLicenseFeatureAllowed(@"automation", NULL));
        assert(automation(@"raw-1"));
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
        assert(!automation(@"raw-1"));
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
        fputs("License diagnostics: actual root 75/76/97 and TrollStore 75/76 wire adapters\n", stderr);
        unsigned mainStatus = mainStatusReads.load(), mainGeneration = mainGenerationReads.load();
        assert([decodeStatus(zx_rootfullPhase6DiagnosticResponse(75, "75cached"))[@"diagnostic_freshness"] isEqual:@"cached"]);
        assert([decodeStatus(TLinkHandleLicenseStatus(NO, @"cached"))[@"diagnostic_freshness"] isEqual:@"cached"]);
        NSString *cachedCapability = [[NSString alloc] initWithData:zx_rootfullPhase6DiagnosticResponse(97, "97cached") encoding:NSUTF8StringEncoding];
        assert([cachedCapability hasSuffix:@" licenseFreshness=cached\r\n"]);
        assert([cachedCapability componentsSeparatedByString:@"\r\n"].count == 2);
        assert(mainStatusReads.load() == mainStatus && mainGenerationReads.load() == mainGeneration);
        assert(!decodeStatus(zx_rootfullPhase6DiagnosticResponse(75, "75"))[@"diagnostic_freshness"]);
        assert(!decodeStatus(TLinkHandleLicenseStatus(NO, @""))[@"diagnostic_freshness"]);
        (void)zx_rootfullPhase6DiagnosticResponse(97, "97");
        assert(mainStatusReads.load() == mainStatus + 3 && mainGenerationReads.load() > mainGeneration);
        assert([decodeStatus(zx_rootfullPhase6DiagnosticResponse(76, "76reload"))[@"cache_invalidated"] boolValue]);
        assert([decodeStatus(TLinkHandleLicenseStatus(YES, @"reload"))[@"cache_invalidated"] boolValue]);
        // Drain process-lifetime work before C++ fixture globals are destroyed.
        dispatch_sync(sTLinkLicenseProbeQueue, ^{ dispatch_source_cancel(sTLinkLicenseProbeTimer); });
        dispatch_sync(sTLinkLicenseRefreshQueue, ^{});
        puts("License Foundation passed: actual snapshot adapter, blocked refresh, 20k hot reads, generation/notification races, 16 cold waiters, expiry/observe and idle timer recovery.");
    }
}
