#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>
#include "../shared/TLinkAXSymbolCache.h"

static const char *const sbsPath="/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices";
static const char *const securityPath="/System/Library/Frameworks/Security.framework/Security";
struct Fixture {
    int sbsHandle=0,securityHandle=0;
    bool sbsOpen=true,securityOpen=true,serverSymbol=true,lockSymbol=true,createSymbol=true,copySymbol=true;
    bool notifyLocked=false,screenOff=false,sbsLocked=false,passcode=false,throwLock=false,taskFailure=false,entitlementError=false;
    std::atomic<unsigned> sbsOpens{0},securityOpens{0},sbsLookups{0},securityLookups{0},closes{0},sbsRefs{0},securityRefs{0};
    std::atomic<unsigned> notifications{0},servers{0},locks{0},tasks{0},copies{0};
};
static std::unique_ptr<Fixture> fixture;
static std::unique_ptr<TLinkAXSymbols::Cache> sbsCache,securityCache;
static NSDictionary *entitlements;
static void reset(){
    fixture.reset(new Fixture);
    sbsCache.reset(new TLinkAXSymbols::Cache(sbsPath,"SBSSpringBoardServerPort","SBGetScreenLockStatus"));
    securityCache.reset(new TLinkAXSymbols::Cache(securityPath,"SecTaskCreateFromSelf","SecTaskCopyValueForEntitlement"));
    entitlements=@{@"inspection":@YES,@"api":@NO,@"setup":@[@"value"]};
}
static TLinkAXSymbols::Cache &fixtureCache(const char *path){
    if(!std::strcmp(path,sbsPath))return *sbsCache;
    assert(!std::strcmp(path,securityPath));return *securityCache;
}
static BOOL TLinkNotifyFlag(const char *name){
    ++fixture->notifications;
    if(!std::strcmp(name,"com.apple.springboard.lockstate"))return fixture->notifyLocked;
    assert(!std::strcmp(name,"com.apple.springboard.hasBlankedScreen"));return fixture->screenOff;
}
static mach_port_t fixtureServer(){++fixture->servers;return 123;}
static void fixtureLockStatus(mach_port_t port,BOOL *locked,BOOL *passcode){
    assert(port==123&&locked&&passcode);++fixture->locks;
    if(fixture->throwLock)[NSException raise:@"AXSymbolsFixture" format:@"lock"];
    *locked=fixture->sbsLocked;*passcode=fixture->passcode;
}
static CFTypeRef fixtureCreateTask(CFAllocatorRef allocator){
    assert(allocator==kCFAllocatorDefault);++fixture->tasks;
    return fixture->taskFailure?NULL:CFRetain(CFSTR("fixture-task"));
}
static CFTypeRef fixtureCopyEntitlement(CFTypeRef task,CFStringRef name,CFErrorRef *error){
    assert(task&&name&&error);++fixture->copies;
    if(fixture->entitlementError)*error=CFErrorCreate(kCFAllocatorDefault,CFSTR("AXSymbolsFixture"),1,NULL);
    id value=entitlements[(__bridge NSString *)name];
    return value?CFRetain((__bridge CFTypeRef)value):NULL;
}
static void *fixtureOpen(const char *path,int flags){
    assert(flags==(RTLD_LAZY|RTLD_LOCAL));
    if(!std::strcmp(path,sbsPath)){
        ++fixture->sbsOpens;if(!fixture->sbsOpen)return nullptr;++fixture->sbsRefs;return &fixture->sbsHandle;
    }
    assert(!std::strcmp(path,securityPath));++fixture->securityOpens;
    if(!fixture->securityOpen)return nullptr;++fixture->securityRefs;return &fixture->securityHandle;
}
static void *fixtureLookup(void *handle,const char *name){
    if(handle==&fixture->sbsHandle){
        ++fixture->sbsLookups;
        if(!std::strcmp(name,"SBSSpringBoardServerPort"))return fixture->serverSymbol?reinterpret_cast<void *>(&fixtureServer):nullptr;
        assert(!std::strcmp(name,"SBGetScreenLockStatus"));return fixture->lockSymbol?reinterpret_cast<void *>(&fixtureLockStatus):nullptr;
    }
    assert(handle==&fixture->securityHandle);++fixture->securityLookups;
    if(!std::strcmp(name,"SecTaskCreateFromSelf"))return fixture->createSymbol?reinterpret_cast<void *>(&fixtureCreateTask):nullptr;
    assert(!std::strcmp(name,"SecTaskCopyValueForEntitlement"));return fixture->copySymbol?reinterpret_cast<void *>(&fixtureCopyEntitlement):nullptr;
}
static int fixtureClose(void *handle){
    ++fixture->closes;
    if(handle==&fixture->sbsHandle)assert(fixture->sbsRefs.fetch_sub(1)>1);
    else{assert(handle==&fixture->securityHandle);assert(fixture->securityRefs.fetch_sub(1)>1);}
    return 0;
}
namespace Current {
#include "AXSymbolsUnderTest.inc"
}
namespace Legacy {
#include "AXSymbolsLegacy.inc"
}
static NSDictionary *lockState(bool current){return current?Current::TLinkAXLockState():Legacy::TLinkAXLockState();}
static id entitlement(bool current,NSString *name){return current?Current::TLinkAXEntitlementValue(name):Legacy::TLinkAXEntitlementValue(name);}
static void parityCases(){
    for(unsigned mask=0;mask<32;++mask){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            reset();fixture->notifyLocked=(mask&1)!=0;fixture->screenOff=(mask&2)!=0;fixture->sbsLocked=(mask&4)!=0;
            fixture->passcode=(mask&8)!=0;fixture->throwLock=(mask&16)!=0;
            NSDictionary *value=lockState(current);
            if(current)assert([value isEqual:expected]);else expected=value;
            assert(fixture->notifications==2&&fixture->servers==1&&fixture->locks==1);
        }
    }
    for(unsigned scenario=0;scenario<7;++scenario){
        NSArray *expected=nil;
        for(bool current:{false,true}){
            reset();
            switch(scenario){case 0:break;case 1:fixture->securityOpen=false;break;case 2:fixture->createSymbol=false;break;
                case 3:fixture->copySymbol=false;break;case 4:fixture->taskFailure=true;break;case 5:fixture->entitlementError=true;break;
                case 6:entitlements=@{@"inspection":@"true",@"api":@42,@"setup":@{ @"key":@"value" }};break;}
            NSMutableArray *values=[NSMutableArray array];
            for(NSString *name in @[@"inspection",@"api",@"setup",@"missing"])[values addObject:entitlement(current,name)?:[NSNull null]];
            if(current)assert([values isEqual:expected]);else expected=[values copy];
        }
    }
}
static void warmAndLiveCases(){
    for(bool current:{false,true}){
        reset();
        for(unsigned n=0;n<10000;++n){@autoreleasepool{
            fixture->notifyLocked=(n&1)!=0;fixture->screenOff=(n&2)!=0;fixture->sbsLocked=(n&4)!=0;fixture->passcode=(n&8)!=0;
            NSDictionary *value=lockState(current);
            assert([value[@"locked"] boolValue]==(fixture->notifyLocked||fixture->sbsLocked));
            assert([value[@"screen_off"] boolValue]==fixture->screenOff&&[value[@"passcode_enabled"] boolValue]==fixture->passcode);
            entitlements=@{@"inspection":@(n)};id read=entitlement(current,@"inspection");assert([read unsignedIntValue]==n);
        }}
        assert(fixture->notifications==20000&&fixture->servers==10000&&fixture->locks==10000&&fixture->tasks==10000&&fixture->copies==10000);
        assert(fixture->sbsOpens==(current?1U:10000U)&&fixture->securityOpens==(current?1U:10000U));
        assert(fixture->sbsLookups==(current?2U:20000U)&&fixture->securityLookups==(current?2U:20000U));
        assert(fixture->closes==0);
    }
}
static void retryCases(){
    reset();fixture->sbsOpen=fixture->securityOpen=false;
    assert(![lockState(true)[@"locked"] boolValue]);assert(!entitlement(true,@"inspection"));
    fixture->sbsOpen=fixture->securityOpen=true;fixture->lockSymbol=fixture->copySymbol=false;
    assert(![lockState(true)[@"locked"] boolValue]);assert(!entitlement(true,@"inspection"));
    assert(fixture->sbsLookups==2&&fixture->securityLookups==2);
    fixture->lockSymbol=fixture->copySymbol=true;fixture->sbsLocked=true;
    assert([lockState(true)[@"locked"] boolValue]);assert([entitlement(true,@"inspection") boolValue]);
    assert(fixture->sbsOpens==2&&fixture->securityOpens==2&&fixture->sbsLookups==3&&fixture->securityLookups==3);
    fixture->taskFailure=true;assert(!entitlement(true,@"inspection"));fixture->taskFailure=false;
    entitlements=@{};assert(!entitlement(true,@"inspection"));
    NSMutableString *source=[@"fresh mutable value" mutableCopy];entitlements=@{@"inspection":source};
    id held;@autoreleasepool{held=entitlement(true,@"inspection");}
    assert(held==source);[source setString:@"changed"];assert([entitlement(true,@"inspection") isEqualToString:@"changed"]);
    entitlements=@{};assert([held isEqualToString:@"changed"]);assert(!entitlement(true,@"inspection"));
    fixture->throwLock=true;assert(![lockState(true)[@"locked"] boolValue]);
    fixture->throwLock=false;assert([lockState(true)[@"locked"] boolValue]);
    assert(fixture->sbsOpens==2&&fixture->securityOpens==2&&fixture->sbsLookups==3&&fixture->securityLookups==3);
}
static void concurrentCases(){
    reset();lockState(true);entitlement(true,@"inspection");
    const unsigned beforeNotifications=fixture->notifications,beforeCopies=fixture->copies;
    std::vector<std::thread> threads;
    for(unsigned worker=0;worker<8;++worker)threads.emplace_back([]{
        for(unsigned n=0;n<1000;++n){@autoreleasepool{
            assert(![Current::TLinkAXLockState()[@"locked"] boolValue]);
            assert([Current::TLinkAXEntitlementValue(@"inspection") boolValue]);
        }}
    });
    for(auto &thread:threads)thread.join();
    assert(fixture->notifications==beforeNotifications+16000&&fixture->copies==beforeCopies+8000);
    assert(fixture->sbsOpens==1&&fixture->securityOpens==1&&fixture->sbsLookups==2&&fixture->securityLookups==2);
}
int main(){@autoreleasepool{
    std::puts("AX symbols Foundation: actual/frozen lock/entitlement helpers, controlled loader/notify/providers, real CF values");
    parityCases();warmAndLiveCases();retryCases();concurrentCases();entitlements=nil;
    std::puts("AX symbols passed: frozen lock/entitlement/fallback/exception replies, 10k fresh lock and entitlement reads with one open/two lookups per library, missing/partial retry, unchanged aliases/error/CF ownership and 8k concurrent reads. Private framework/device qualification pending.");
}return 0;}
