#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <cassert>
#include <atomic>
#include <thread>
#include <vector>
#include <stdexcept>
#include <cstdio>

// The fake task is a retained CF object; leave the SDK's opaque SecTaskRef alone.
using FixtureSecTaskRef = CFTypeRef;
static NSMutableDictionary *providerValues;
static NSMutableSet *providerErrors;
static bool taskFailure=false;
static int copyFailure=0;
static std::atomic<unsigned> taskCalls{0},valueCalls{0},copyCalls{0};
static std::atomic<unsigned> retainCalls{0};
static std::atomic<int> ownedCF{0};
static CFTypeRef fixtureRetain(CFTypeRef value){assert(value);++retainCalls;++ownedCF;return CFRetain(value);}
static void fixtureRelease(CFTypeRef value){assert(value&&ownedCF>0);--ownedCF;CFRelease(value);}
static FixtureSecTaskRef fixtureCreateTask(CFAllocatorRef allocator){(void)allocator;++taskCalls;return taskFailure?NULL:fixtureRetain(CFSTR("fixture-task"));}
static CFTypeRef fixtureCopyEntitlement(FixtureSecTaskRef task,CFStringRef entitlement,CFErrorRef *error){
    assert(task&&error&&!*error);++valueCalls;
    NSString *key=(__bridge NSString *)entitlement;
    if([providerErrors containsObject:key]){*error=CFErrorCreate(kCFAllocatorDefault,CFSTR("fixture-error"),1,NULL);assert(*error);++ownedCF;}
    id value=providerValues[key];return value?fixtureRetain((__bridge CFTypeRef)value):NULL;
}
static CFPropertyListRef fixtureDeepCopy(CFAllocatorRef allocator,CFPropertyListRef value,CFOptionFlags options){
    ++copyCalls;
    if(copyFailure==1)return NULL;
    if(copyFailure==2)[NSException raise:@"FixtureCopy" format:@"copy"];
    if(copyFailure==3)throw std::runtime_error("copy");
    CFPropertyListRef result=CFPropertyListCreateDeepCopy(allocator,value,options);if(result)++ownedCF;return result;
}
namespace Current {
#include "VPNEntitlementsUnderTest.inc"
}
namespace Legacy {
#include "VPNEntitlementsLegacy.inc"
}
namespace Previous {
#include "VPNEntitlementsPrevious.inc"
}
namespace Retry {
#include "VPNEntitlementsUnderTest.inc"
}
static NSArray<NSString *> *keys(){return @[
    @"com.apple.developer.networking.vpn.api",@"com.apple.developer.networking.networkextension",
    @"com.apple.private.networkextension.configuration",@"keychain-access-groups",
    @"com.apple.SystemConfiguration.SCPreferences-write-access",@"com.apple.SystemConfiguration.SCDynamicStore-write-access",
    @"com.apple.managedconfiguration.profiled-access",@"com.apple.managedconfiguration.mdmd-access",
    @"user-preference-read",@"user-preference-write"];
}
static void reset(){
    assert(ownedCF==0);taskFailure=false;copyFailure=0;taskCalls=0;valueCalls=0;copyCalls=0;retainCalls=0;
    providerErrors=[NSMutableSet set];
    providerValues=[@{keys()[0]:@[@"allow-vpn"],keys()[1]:@[@"packet-tunnel-provider"],
        keys()[2]:@[@"super"],keys()[3]:@[@"com.apple.managed.vpn.shared"],
        keys()[4]:@[@"preferences.plist"],keys()[5]:@(true),keys()[6]:@(true),
        keys()[7]:@(true),keys()[8]:@(true),keys()[9]:@(true)} mutableCopy];
}
static NSDictionary *readCache(NSMutableDictionary *cache){NSDictionary *result=Current::TLinkVPNEntitlementProbeUsingCache(cache);assert(ownedCF==0);return result;}
static void parityAndWarmCases(){
    NSArray *variants=@[@[],@[@"allow-vpn",@"packet-tunnel-provider",@"super",@"com.apple.managed.vpn.shared",@"preferences.plist",@"true"],@"true",@"allow-vpn",@(true),@(false),@[@1,@"true",@{}],@{},@42];
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        reset();NSMutableDictionary *cache=[NSMutableDictionary dictionary];
        for(unsigned k=0;k<10;++k){if((n+k)%13==0)[providerValues removeObjectForKey:keys()[k]];else providerValues[keys()[k]]=variants[(n+k*3)%variants.count];}
        NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();assert(ownedCF==0);
        NSDictionary *cold=readCache(cache);assert([cold isEqual:expected]&&cache.count==10);
        assert(![cold[@"vpn_api_values"] isKindOfClass:[NSMutableArray class]]);
        const unsigned beforeTasks=taskCalls.load(),beforeValues=valueCalls.load();
        for(unsigned repeat=0;repeat<10;++repeat)assert([readCache(cache) isEqual:expected]);
        assert(taskCalls==beforeTasks&&valueCalls==beforeValues);
    }}
    reset();NSMutableDictionary *cache=[NSMutableDictionary dictionary];NSDictionary *held;
    @autoreleasepool{held=readCache(cache);}
    assert([held[@"allow_vpn"] boolValue]);
    for(unsigned n=0;n<10000;++n)assert([readCache(cache) isEqual:held]);
    assert(taskCalls==1&&valueCalls==10&&cache.count==10);
}
static void faultAndRetryCases(){
    for(unsigned failed=0;failed<10;++failed){
        reset();NSMutableDictionary *cache=[NSMutableDictionary dictionary];[providerErrors addObject:keys()[failed]];
        // Errors with a value preserve its current meaning; errors without one also retry.
        if(failed%2==0)[providerValues removeObjectForKey:keys()[failed]];
        NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();assert(ownedCF==0);
        assert([readCache(cache) isEqual:expected]&&cache.count==9);
        const unsigned before=valueCalls.load();assert([readCache(cache) isEqual:expected]);assert(valueCalls==before+1);
        taskFailure=true;NSDictionary *unavailable=Legacy::TLinkVPNEntitlementProbe();assert([readCache(cache) isEqual:unavailable]&&cache.count==9);
        taskFailure=false;[providerErrors removeAllObjects];readCache(cache);assert(cache.count==10);
        const unsigned warm=valueCalls.load();readCache(cache);assert(valueCalls==warm);
    }
    for(int fault=1;fault<=3;++fault){
        reset();copyFailure=fault;NSMutableDictionary *cache=[NSMutableDictionary dictionary];
        NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();assert([readCache(cache) isEqual:expected]&&cache.count==0);
        assert(valueCalls==20&&copyCalls==10);copyFailure=0;assert([readCache(cache) isEqual:expected]&&cache.count==10);
        const unsigned before=valueCalls.load();readCache(cache);assert(valueCalls==before);
    }
    reset();taskFailure=true;NSMutableDictionary *cache=[NSMutableDictionary dictionary];
    assert([readCache(cache) isEqual:Legacy::TLinkVPNEntitlementProbe()]&&cache.count==0&&valueCalls==0);
    taskFailure=false;readCache(cache);assert(cache.count==10&&valueCalls==10);
}
static void ownershipCases(){
    reset();NSMutableDictionary *cache=[NSMutableDictionary dictionary];
    NSMutableString *text=[NSMutableString stringWithString:@"allow-vpn"];
    NSMutableArray *values=[NSMutableArray arrayWithObject:text];providerValues[keys()[0]]=values;
    NSDictionary *held=readCache(cache);[text setString:@"changed"];[values removeAllObjects];
    assert([held[@"allow_vpn"] boolValue]&&[readCache(cache)[@"allow_vpn"] boolValue]);
    assert([held[@"vpn_api_values"][0] isEqualToString:@"allow-vpn"]);
    // Caller-visible arrays cannot overwrite the shared memo on a later read.
    bool rejected=false;@try{[(NSMutableArray *)held[@"vpn_api_values"] addObject:@"mutated"];}@catch(NSException *exception){(void)exception;rejected=true;}
    assert(rejected&&[readCache(cache)[@"vpn_api_values"] isEqual:@[@"allow-vpn"]]);
    [cache removeAllObjects];assert([held[@"allow_vpn"] boolValue]);
    assert(![readCache(cache)[@"allow_vpn"] boolValue]);
}
static void concurrentPublicCases(){
    reset();NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();assert(ownedCF==0);taskCalls=0;valueCalls=0;retainCalls=0;
    std::vector<std::thread> workers;
    for(unsigned worker=0;worker<8;++worker)workers.emplace_back([expected]{@autoreleasepool{
        for(unsigned n=0;n<1000;++n){@autoreleasepool{assert([Current::TLinkVPNEntitlementProbe() isEqual:expected]);}}
    }});
    for(std::thread &worker:workers)worker.join();
    assert(taskCalls==1&&valueCalls==10&&retainCalls==11&&ownedCF==0);
    NSDictionary *held;
    @autoreleasepool{held=Current::TLinkVPNEntitlementProbe();}
    assert([held isEqual:expected]);
    for(unsigned n=0;n<10000;++n){@autoreleasepool{assert(Current::TLinkVPNEntitlementProbe()==held);}}
    assert(retainCalls==11&&ownedCF==0);
    // Compare the actual preceding wrapper: it still retains ten CF values per warm call.
    assert([Previous::TLinkVPNEntitlementProbe() isEqual:held]);
    const unsigned before=retainCalls.load();
    for(unsigned n=0;n<64;++n)assert([Previous::TLinkVPNEntitlementProbe() isEqual:held]);
    assert(retainCalls==before+640);
}
static void publicRetryAndSnapshotCases(){
    reset();NSDictionary *resolvedValues=[providerValues copy];[providerValues removeAllObjects];
    [providerErrors addObjectsFromArray:keys()];
    assert([Retry::TLinkVPNEntitlementProbe() isEqual:Legacy::TLinkVPNEntitlementProbe()]);
    for(unsigned key=0;key<10;++key){
        [providerErrors removeObject:keys()[key]];
        providerValues[keys()[key]]=resolvedValues[keys()[key]];
        if(key==4){
            taskFailure=true;
            assert([Retry::TLinkVPNEntitlementProbe() isEqual:Legacy::TLinkVPNEntitlementProbe()]);
            taskFailure=false;
        }
        if(key<3){
            copyFailure=(int)key+1;
            NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();
            assert([Retry::TLinkVPNEntitlementProbe() isEqual:expected]);
            copyFailure=0;
        }
        NSDictionary *expected=Legacy::TLinkVPNEntitlementProbe();
        assert([Retry::TLinkVPNEntitlementProbe() isEqual:expected]&&ownedCF==0);
    }
    NSDictionary *held;
    @autoreleasepool{held=Retry::TLinkVPNEntitlementProbe();}
    assert([held[@"allow_vpn"] boolValue]);
    bool rejected=false;
    @try{[(NSMutableDictionary *)held setObject:@0 forKey:@"allow_vpn"];}@catch(NSException *exception){(void)exception;rejected=true;}
    assert(rejected);
    rejected=false;
    @try{[(NSMutableArray *)held[@"vpn_api_values"] addObject:@"changed"];}@catch(NSException *exception){(void)exception;rejected=true;}
    assert(rejected);
    [providerValues removeAllObjects];taskFailure=true;
    const unsigned tasks=taskCalls.load(),values=valueCalls.load(),copies=copyCalls.load(),retains=retainCalls.load();
    for(unsigned n=0;n<1000;++n){@autoreleasepool{assert(Retry::TLinkVPNEntitlementProbe()==held);}}
    assert(taskCalls==tasks&&valueCalls==values&&copyCalls==copies&&retainCalls==retains&&ownedCF==0);
}
int main(){@autoreleasepool{
    puts("VPN diagnostics Foundation: actual/frozen entitlement normalization, success-only immutable memo and CF ownership");
    parityAndWarmCases();faultAndRetryCases();ownershipCases();concurrentPublicCases();publicRetryAndSnapshotCases();
    puts("VPN diagnostics cache passed: 1000 frozen shapes, 10k warm reads, absent values, ten independent error retries, task/copy NS/C++ failures, pool/mutable ownership and 8k concurrent public calls. Completed snapshots reuse immutable results without warm CF retains (640 preceding retains over 64 calls). No real entitlement or VPN state changed.");
}return 0;}
