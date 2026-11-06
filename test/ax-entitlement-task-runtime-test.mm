#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <unordered_set>
#include <vector>
#include "../shared/TLinkAXSymbolCache.h"
#include "../shared/TLinkAXAdmission.h"
#include "../shared/TLinkAXSnapshotOutput.h"
#include "../shared/TLinkAXWireOutput.h"
#include "AXCapabilityConstants.inc"

static NSString *const TLinkAXBackendName=@"axruntime_numeric_v1";
static const char *const securityPath="/System/Library/Frameworks/Security.framework/Security";
static const char *const createName="SecTaskCreateFromSelf",*const copyName="SecTaskCopyValueForEntitlement";
static NSArray<NSString *> *names(){return @[@"com.apple.private.accessibility.inspection",@"com.apple.accessibility.api",@"com.apple.private.accessibility.look-me-up-setup"];}
static int marker;
static void *sTLinkAXCreateApp=&marker,*sTLinkAXCopyAttribute=&marker,*sTLinkAXSetTimeout=&marker,*sTLinkAXValueGetValue=&marker,*sTLinkAXHitTest=&marker;
static BOOL sTLinkAXFrameworkLoaded=YES,sTLinkAccessibilityLibraryLoaded=YES,sTLinkAXEnableSymbol=YES,sTLinkAXAutomationSymbol=YES,sTLinkAXRequestingClientSymbol=YES,sTLinkAXOverrideClientSymbol=YES;
struct Fixture {
    int handle=0;
    bool libraryReady=true,createReady=true,copyReady=true,prepared=true,locked=false,recordReads=true;
    unsigned failFirstCreates=0,errorMask=0,failCreateAt=0,failCopyAt=0;
    int createFault=0,copyFault=0,lookupFault=0;
    std::atomic<unsigned> opens{0},closes{0},references{0},lookups{0},creates{0},taskDrops{0},copies{0},errorCreates{0},errorDrops{0};
    std::atomic<unsigned> prepares{0},locks{0},fronts{0};
    std::mutex mutex;
    std::unordered_set<CFTypeRef> tasks,errors;
    std::vector<uint64_t> readTasks;
};
static std::unique_ptr<Fixture> fixture;
static std::unique_ptr<TLinkAXSymbols::Cache> cache;
static std::atomic<uint64_t> taskSequence{0};
static NSArray *providerValues;
static NSDictionary *foreground;
static void fault(int kind){
    if(kind==1)[NSException raise:@"AXEntitlementFixture" format:@"fault"];
    if(kind==2)throw std::runtime_error("fault");
}
@interface FixtureBoolean:NSObject
@property(nonatomic) int faultKind;
@end
@implementation FixtureBoolean
-(BOOL)boolValue{fault(self.faultKind);return YES;}
@end
static void reset(unsigned seed=0){
    if(fixture){assert(fixture->tasks.empty()&&fixture->errors.empty());}
    fixture.reset(new Fixture);cache.reset(new TLinkAXSymbols::Cache(securityPath,createName,copyName));
    providerValues=@[@YES,@NO,@"true"];
    foreground=@{@"ok":@YES,@"bundle_id":[NSString stringWithFormat:@"com.fixture.%u.测试",seed],@"pid":@(100+seed),@"source":@"controlled"};
    sTLinkAXFrameworkLoaded=(seed&1)==0;sTLinkAccessibilityLibraryLoaded=(seed&2)==0;
    sTLinkAXEnableSymbol=(seed&4)==0;sTLinkAXAutomationSymbol=(seed&8)==0;sTLinkAXRequestingClientSymbol=(seed&16)==0;sTLinkAXOverrideClientSymbol=(seed&32)==0;
    sTLinkAXCreateApp=(seed&64)?nullptr:&marker;sTLinkAXCopyAttribute=(seed&128)?nullptr:&marker;sTLinkAXSetTimeout=(seed&256)?nullptr:&marker;
    sTLinkAXValueGetValue=(seed&512)?nullptr:&marker;sTLinkAXHitTest=(seed&1024)?nullptr:&marker;
}
static TLinkAXSymbols::Cache &fixtureCache(const char *path){assert(!std::strcmp(path,securityPath));return *cache;}
static BOOL TLinkAXPrepare(){++fixture->prepares;return fixture->prepared;}
static NSDictionary *TLinkAXLockState(){++fixture->locks;return @{@"locked":@(fixture->locked),@"screen_off":@NO,@"passcode_enabled":@YES};}
static NSDictionary *TLinkAXCopyFrontmostContext(){++fixture->fronts;return foreground;}
static CFTypeRef fixtureCreateTask(CFAllocatorRef allocator){
    assert(allocator==kCFAllocatorDefault);const unsigned call=++fixture->creates;
    if(call==fixture->failCreateAt)fault(fixture->createFault);
    if(call<=fixture->failFirstCreates)return NULL;
    const uint64_t sequence=++taskSequence;
    CFDataRef task=CFDataCreate(kCFAllocatorDefault,reinterpret_cast<const UInt8 *>(&sequence),sizeof(sequence));assert(task);
    {std::lock_guard<std::mutex> lock(fixture->mutex);assert(fixture->tasks.insert(task).second);}
    return task;
}
static CFTypeRef fixtureCopyValue(CFTypeRef task,CFStringRef name,CFErrorRef *error){
    assert(task&&name&&error&&!*error);const unsigned call=++fixture->copies;
    uint64_t sequence=0;assert(CFGetTypeID(task)==CFDataGetTypeID()&&CFDataGetLength((CFDataRef)task)==(CFIndex)sizeof(sequence));
    std::memcpy(&sequence,CFDataGetBytePtr((CFDataRef)task),sizeof(sequence));
    {std::lock_guard<std::mutex> lock(fixture->mutex);assert(fixture->tasks.count(task)==1);if(fixture->recordReads)fixture->readTasks.push_back(sequence);}
    const NSUInteger index=[names() indexOfObject:(__bridge NSString *)name];assert(index<3);
    if((fixture->errorMask&(1U<<index))||call==fixture->failCopyAt){
        *error=CFErrorCreate(kCFAllocatorDefault,CFSTR("AXEntitlementFixture"),1,NULL);assert(*error);++fixture->errorCreates;
        std::lock_guard<std::mutex> lock(fixture->mutex);assert(fixture->errors.insert(*error).second);
    }
    if(call==fixture->failCopyAt)fault(fixture->copyFault);
    id value=providerValues[index];return value==[NSNull null]?NULL:CFRetain((__bridge CFTypeRef)value);
}
static void fixtureRelease(CFTypeRef value){
    assert(value);
    {std::lock_guard<std::mutex> lock(fixture->mutex);
        if(fixture->tasks.erase(value))++fixture->taskDrops;
        else{assert(fixture->errors.erase(value)==1);++fixture->errorDrops;}}
    CFRelease(value);
}
static void *fixtureOpen(const char *path,int flags){
    assert(!std::strcmp(path,securityPath)&&flags==(RTLD_LAZY|RTLD_LOCAL));++fixture->opens;
    if(!fixture->libraryReady)return nullptr;
    ++fixture->references;return &fixture->handle;
}
static void *fixtureLookup(void *handle,const char *name){
    assert(handle==&fixture->handle);++fixture->lookups;fault(fixture->lookupFault);
    if(!std::strcmp(name,createName))return fixture->createReady?reinterpret_cast<void *>(&fixtureCreateTask):nullptr;
    assert(!std::strcmp(name,copyName));return fixture->copyReady?reinterpret_cast<void *>(&fixtureCopyValue):nullptr;
}
static int fixtureClose(void *handle){assert(handle==&fixture->handle&&fixture->references.fetch_sub(1)>1);++fixture->closes;return 0;}
namespace Current {
#include "AXEntitlementTaskUnderTest.inc"
#include "AXCapabilityUnderTest.inc"
}
namespace Legacy {
#include "AXEntitlementTaskLegacy.inc"
#include "AXCapabilityLegacy.inc"
}
static NSDictionary *read(bool current){return current?Current::TLinkAXCapabilitySnapshot():Legacy::TLinkAXCapabilitySnapshot();}
static void checkRetired(){
    std::lock_guard<std::mutex> lock(fixture->mutex);
    const bool retired=fixture->tasks.empty()&&fixture->errors.empty()&&fixture->errorCreates==fixture->errorDrops;
    if(!retired)std::fprintf(stderr,"AX capability owners remain: tasks=%zu errors=%zu creates=%u taskDrops=%u errorCreates=%u errorDrops=%u\n",
        fixture->tasks.size(),fixture->errors.size(),fixture->creates.load(),fixture->taskDrops.load(),fixture->errorCreates.load(),fixture->errorDrops.load());
    assert(retired);
}
static void goldenCases(){
    NSArray *variants=@[@YES,@NO,@"true",@"0",@42,@[],@{},[NSNull null]];
    for(unsigned n=0;n<512;++n){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset(n);fixture->prepared=(n&1)==0;fixture->locked=(n&2)!=0;fixture->errorMask=n%8;fixture->failFirstCreates=n%4;
                if(n%17==0)fixture->libraryReady=false;
                if(n%19==0)fixture->createReady=false;
                if(n%23==0)fixture->copyReady=false;
                providerValues=@[variants[n%8],variants[(n/3)%8],variants[(n/7)%8]];
                NSDictionary *value=read(current);
                if(current){
                    NSMutableDictionary *withLimit=[expected mutableCopy];withLimit[@"max_pending_queries"]=@8;withLimit[@"max_snapshot_string_utf8_bytes"]=@65536;withLimit[@"max_hit_test_string_utf8_bytes"]=@65536;withLimit[@"hard_max_success_wire_bytes"]=@1048576;expected=withLimit;
                    assert([value[@"max_pending_queries"] unsignedIntValue]==TLinkAXAdmission::MaxPending);
                    assert([value[@"hard_max_success_wire_bytes"] unsignedIntegerValue]==TLinkAXWireOutput::MaxSuccessWireBytes);
                    assert([value[@"max_hit_test_string_utf8_bytes"] unsignedIntegerValue]==TLinkAXSnapshotOutput::MaxStringUTF8Bytes);
                    assert([value[@"max_snapshot_string_utf8_bytes"] unsignedIntegerValue]==TLinkAXSnapshotOutput::MaxStringUTF8Bytes);
                    if(![value isEqual:expected])NSLog(@"AX capability parity failure seed=%u expected=%@ actual=%@",n,expected,value);
                    assert([value isEqual:expected]);
                    NSData *oldJSON=[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingSortedKeys error:NULL];
                    NSData *newJSON=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
                    assert(oldJSON&&[newJSON isEqual:oldJSON]);
                }else expected=value;
                assert(fixture->prepares==1&&fixture->locks==1&&fixture->fronts==1);checkRetired();
                if(fixture->libraryReady&&fixture->createReady&&fixture->copyReady){
                    const unsigned failed=fixture->failFirstCreates,successful=failed<3?3-failed:0;
                    assert(fixture->copies==successful&&fixture->creates==(current?(successful?failed+1:3):3));
                    assert(fixture->taskDrops==(current?(successful?1U:0U):successful));
                    if(successful){
                        assert(fixture->readTasks.size()==successful);
                        for(unsigned k=1;k<successful;++k)assert((fixture->readTasks[k]==fixture->readTasks[0])==current);
                    }
                }else assert(fixture->creates==0&&fixture->copies==0);
            }
        }
    }
}
static void warmAndRetryCases(){
    for(bool current:{false,true}){
        reset();fixture->recordReads=false;
        for(unsigned n=0;n<10000;++n){@autoreleasepool{
            providerValues=@[@((n&1)!=0),@((n&2)!=0),@((n&4)!=0)];
            NSDictionary *value=read(current);
            for(unsigned k=0;k<3;++k)assert([value[@"entitlements"][names()[k]] boolValue]==((n&(1U<<k))!=0));
            checkRetired();
        }}
        assert(fixture->creates==(current?10000U:30000U)&&fixture->taskDrops==fixture->creates&&fixture->copies==30000);
    }
    reset();fixture->failFirstCreates=1;
    NSDictionary *value=read(true);assert(![value[@"entitlements"][names()[0]] boolValue]&&[value[@"entitlements"][names()[2]] boolValue]);
    assert(fixture->creates==2&&fixture->copies==2&&fixture->taskDrops==1);checkRetired();
    read(true);assert(fixture->creates==3&&fixture->copies==5&&fixture->taskDrops==2);checkRetired();
    reset();fixture->copyReady=false;read(true);assert(fixture->creates==0);
    fixture->copyReady=true;read(true);assert(fixture->creates==1&&fixture->copies==3);checkRetired();
    // Calls without an explicit owner keep their independent task lifetime.
    reset();for(NSString *name in names())Current::TLinkAXEntitlementValue(name);
    assert(fixture->creates==3&&fixture->taskDrops==3&&fixture->copies==3);checkRetired();
}
static void faultCases(){
    for(unsigned site=0;site<5;++site){
        for(int kind=1;kind<=2;++kind){
            bool caught=false;
            @autoreleasepool{
                reset();
                if(site==0){fixture->failCreateAt=1;fixture->createFault=kind;}
                else if(site<=3){fixture->failCopyAt=site;fixture->copyFault=kind;}
                else{FixtureBoolean *value=[FixtureBoolean new];value.faultKind=kind;providerValues=@[@YES,value,@NO];}
                @try{try{read(true);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXEntitlementFixture"];}
                assert(caught);checkRetired();
            }
            checkRetired();
            fixture->failCreateAt=fixture->failCopyAt=0;providerValues=@[@YES,@YES,@YES];
            assert([read(true)[@"entitlements"][names()[0]] boolValue]);checkRetired();
        }
    }
    for(int kind=1;kind<=2;++kind){
        @autoreleasepool{
            reset();fixture->failCopyAt=1;fixture->copyFault=kind;bool caught=false;
            @try{try{Current::TLinkAXEntitlementValue(names()[0]);}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXEntitlementFixture"];}
            assert(caught&&fixture->taskDrops==1&&fixture->errorDrops==1);checkRetired();
        }
        @autoreleasepool{
            reset();fixture->lookupFault=kind;bool caught=false;
            @try{try{read(true);}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXEntitlementFixture"];}
            assert(caught&&fixture->creates==0);checkRetired();fixture->lookupFault=0;read(true);checkRetired();
        }
    }
}
static void concurrentAndLifetimeCases(){
    reset();fixture->recordReads=false;std::vector<std::thread> threads;
    for(unsigned worker=0;worker<8;++worker)threads.emplace_back([]{
        for(unsigned n=0;n<1000;++n){@autoreleasepool{
            NSDictionary *value=read(true);assert([value[@"entitlements"][names()[0]] boolValue]);
        }}
    });
    for(auto &thread:threads)thread.join();
    assert(fixture->creates==8000&&fixture->taskDrops==8000&&fixture->copies==24000&&fixture->references==1);checkRetired();
    NSDictionary *held=nil;__weak FixtureBoolean *weakValue;
    @autoreleasepool{
        reset();FixtureBoolean *value=[FixtureBoolean new];weakValue=value;providerValues=@[value,@NO,@YES];held=read(true);
        providerValues=@[];checkRetired();
    }
    assert(!weakValue&&[held[@"entitlements"][names()[0]] boolValue]);held=nil;
    for(unsigned n=0;n<128;++n){@autoreleasepool{reset();read(true);checkRetired();}}
}
int main(){@autoreleasepool{
    std::puts("AX capability task Foundation: actual/frozen complete helper/capability, real CF task/error owners and controlled Security/live providers");
    goldenCases();warmAndRetryCases();faultCases();concurrentAndLifetimeCases();providerValues=nil;foreground=nil;
    std::puts("AX capability task passed: 512 frozen graphs/JSON cases, per-key create retry, fresh values, 10k probes with 10k versus30k tasks/unchanged30k reads, one-off ownership, NS/C++ task/error/BOOL/lookup unwind, 8k concurrent probes and 128 balanced lifecycles. Security/device qualification pending.");
}return 0;}
