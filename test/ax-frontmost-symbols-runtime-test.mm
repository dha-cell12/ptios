#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>
#include "../shared/TLinkAXSymbolCache.h"

static const char *const libraryPath="/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices";
static const char *const symbolNames[]={"SBSCopyFrontmostApplicationDisplayIdentifier","SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
    "SBSSpringBoardServerPort","SBFrontmostApplicationDisplayIdentifier"};
struct Fixture {
    int handle=0;
    bool libraryReady=true,available[4]={true,true,true,true},recordCalls=true;
    int throwCopy=-1,copyFault=0,legacyFault=0,throwLookup=-1,lookupFault=0;
    std::atomic<unsigned> opens{0},closes{0},references{0},lookups{0},copyCalls[2],servers{0},legacyCalls{0},createdCF{0},releasedCF{0};
    std::atomic<unsigned> slotLookups[4];
    Fixture(){copyCalls[0]=0;copyCalls[1]=0;for(unsigned n=0;n<4;++n)slotLookups[n]=0;}
};
static std::unique_ptr<Fixture> fixture;
static std::unique_ptr<TLinkAXSymbols::Cache> copyCache;
static std::unique_ptr<TLinkAXSymbols::Symbol> serverSymbol,legacySymbol;
static NSArray *copyValues;
static NSData *legacyBytes;
static NSMutableArray *providerCalls;
static void reset(){
    fixture.reset(new Fixture);
    copyCache.reset(new TLinkAXSymbols::Cache(libraryPath,symbolNames[0],symbolNames[1]));
    serverSymbol.reset(new TLinkAXSymbols::Symbol(symbolNames[2]));
    legacySymbol.reset(new TLinkAXSymbols::Symbol(symbolNames[3]));
    copyValues=@[@"fixture.first",@"fixture.second"];
    legacyBytes=[@"fixture.legacy" dataUsingEncoding:NSUTF8StringEncoding];providerCalls=[NSMutableArray array];
}
static void fault(int kind){
    if(kind==1)[NSException raise:@"AXFrontmostFixture" format:@"provider"];
    if(kind==2)throw std::runtime_error("provider");
}
static CFStringRef fixtureCopy(unsigned index){
    ++fixture->copyCalls[index];if(fixture->recordCalls)[providerCalls addObject:@(index)];
    if(fixture->throwCopy==(int)index)fault(fixture->copyFault);
    id value=copyValues[index];if(value==[NSNull null])return NULL;
    ++fixture->createdCF;return (CFStringRef)CFRetain((__bridge CFTypeRef)value);
}
static CFStringRef fixtureFirst(){return fixtureCopy(0);}
static CFStringRef fixtureSecond(){return fixtureCopy(1);}
static mach_port_t fixtureServer(){
    ++fixture->servers;if(fixture->recordCalls)[providerCalls addObject:@"server"];return 123;
}
static void fixtureLegacy(mach_port_t port,char *buffer){
    assert(port==123&&buffer&&legacyBytes.length<512);
    ++fixture->legacyCalls;if(fixture->recordCalls)[providerCalls addObject:@"legacy"];
    fault(fixture->legacyFault);
    if(legacyBytes.length)std::memcpy(buffer,legacyBytes.bytes,legacyBytes.length);
}
static void *fixtureOpen(const char *path,int flags){
    assert(!std::strcmp(path,libraryPath)&&flags==(RTLD_LAZY|RTLD_LOCAL));++fixture->opens;
    if(!fixture->libraryReady)return nullptr;
    ++fixture->references;return &fixture->handle;
}
static void *fixtureLookup(void *handle,const char *name){
    assert(handle==&fixture->handle);++fixture->lookups;
    for(unsigned index=0;index<4;++index){
        if(std::strcmp(name,symbolNames[index]))continue;
        ++fixture->slotLookups[index];
        if(fixture->throwLookup==(int)index)fault(fixture->lookupFault);
        if(!fixture->available[index])return nullptr;
        switch(index){case 0:return reinterpret_cast<void *>(&fixtureFirst);case 1:return reinterpret_cast<void *>(&fixtureSecond);
            case 2:return reinterpret_cast<void *>(&fixtureServer);case 3:return reinterpret_cast<void *>(&fixtureLegacy);}
    }
    assert(false);return nullptr;
}
static int fixtureClose(void *handle){
    assert(handle==&fixture->handle&&fixture->references.fetch_sub(1)>1);++fixture->closes;return 0;
}
static void fixtureRelease(CFTypeRef value){assert(value);++fixture->releasedCF;CFRelease(value);}
namespace Current {
#include "AXFrontmostUnderTest.inc"
}
namespace Legacy {
#include "AXFrontmostLegacy.inc"
}
namespace Preceding {
#include "AXFrontmostBeforeLazy.inc"
}
static NSString *read(bool current){return current?Current::TLinkAXFrontmostBundleID():Legacy::TLinkAXFrontmostBundleID();}
static void checkCF(){assert(fixture->createdCF==fixture->releasedCF);}
static void parityCases(){
    NSArray *values=@[[NSNull null],@"",@"com.fixture.Ứng-dụng.测试",@"id\0tail"];
    for(unsigned n=0;n<256;++n){
        NSString *expected=nil;NSArray *expectedCalls=nil;unsigned expectedCopies=0;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();fixture->libraryReady=n%17!=0;
                for(unsigned k=0;k<4;++k)fixture->available[k]=(n&(1U<<k))!=0;
                copyValues=@[values[(n/3)%values.count],values[(n/7)%values.count]];
                if(n%5==0)legacyBytes=[NSData data];
                if(n%11==0){const unsigned char invalid[]={0xff,0};legacyBytes=[NSData dataWithBytes:invalid length:sizeof(invalid)];}
                NSString *value=read(current);
                if(current){
                    assert(value==expected||[value isEqualToString:expected]);
                    assert([providerCalls isEqual:expectedCalls]&&fixture->createdCF==expectedCopies);
                }else{expected=value;expectedCalls=[providerCalls copy];expectedCopies=fixture->createdCF;}
                checkCF();
                assert(fixture->references==(fixture->libraryReady?1U:0U));
            }
        }
    }
}
static void warmAndLiveCases(){
    for(unsigned route=0;route<3;++route){
        for(bool current:{false,true}){
            reset();fixture->recordCalls=false;
            for(unsigned n=0;n<10000;++n){@autoreleasepool{
                NSString *fresh=[NSString stringWithFormat:@"com.fixture.%u.测试",n];
                copyValues=@[route==0?(id)fresh:[NSNull null],route==1?(id)fresh:[NSNull null]];
                legacyBytes=[fresh dataUsingEncoding:NSUTF8StringEncoding];
                assert([read(current) isEqualToString:fresh]);checkCF();
            }}
            assert(fixture->opens==(current?1U:10000U)&&fixture->references==(current?1U:10000U)&&fixture->closes==0);
            assert(fixture->lookups==(current?(route==0?1U:(route==1?2U:4U)):(route==0?10000U:(route==1?20000U:40000U))));
            assert(fixture->copyCalls[0]==10000&&fixture->copyCalls[1]==(route?10000U:0U));
            assert(fixture->servers==(route==2?10000U:0U)&&fixture->legacyCalls==(route==2?10000U:0U));
        }
    }
}
static void retryAndLifetimeCases(){
    reset();fixture->libraryReady=false;
    assert(!read(true)&&!read(true)&&fixture->opens==2&&fixture->lookups==0);
    fixture->libraryReady=true;
    for(unsigned k=0;k<4;++k)fixture->available[k]=false;
    assert(!read(true)&&fixture->references==1&&fixture->opens==3);
    fixture->available[0]=true;assert([read(true) isEqualToString:@"fixture.first"]);
    fixture->available[1]=true;copyValues=@[[NSNull null],@"new.second"];
    assert([read(true) isEqualToString:@"new.second"]);
    copyValues=@[[NSNull null],[NSNull null]];fixture->available[2]=true;
    assert(!read(true));fixture->available[3]=true;
    assert([read(true) isEqualToString:@"fixture.legacy"]);
    const unsigned lookups=fixture->lookups;
    for(unsigned k=0;k<4;++k)fixture->available[k]=false;
    NSString *held=nil;
    @autoreleasepool{
        NSMutableString *source=[@"fresh mutable Ứng dụng" mutableCopy];copyValues=@[source,[NSNull null]];
        held=read(true);[source setString:@"later value"];
        assert([held isEqualToString:@"fresh mutable Ứng dụng"]);
        assert([read(true) isEqualToString:@"later value"]);
        copyValues=@[[NSNull null],[NSNull null]];
    }
    assert([held isEqualToString:@"fresh mutable Ứng dụng"]&&fixture->lookups==lookups&&fixture->opens==3&&fixture->references==1);checkCF();
}
static void exceptionCases(){
    for(unsigned route=0;route<2;++route){
        for(int kind=1;kind<=2;++kind){
            for(bool current:{false,true}){
                @autoreleasepool{
                    reset();if(route==0){fixture->throwCopy=0;fixture->copyFault=kind;}
                    else{copyValues=@[[NSNull null],[NSNull null]];fixture->legacyFault=kind;}
                    bool caught=false;NSString *value=nil;
                    @try{try{value=read(current);}catch(const std::runtime_error &){caught=kind==2;}}
                    @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXFrontmostFixture"];}
                    assert(caught==(route==0||kind==2)&&!value);checkCF();
                    fixture->throwCopy=-1;fixture->legacyFault=0;
                    assert(read(current));checkCF();
                }
            }
        }
    }
    for(int index=0;index<4;++index){
        for(int kind=1;kind<=2;++kind){
            @autoreleasepool{
                reset();copyValues=@[[NSNull null],[NSNull null]];fixture->throwLookup=index;fixture->lookupFault=kind;bool caught=false;
                @try{try{read(true);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXFrontmostFixture"];}
                assert(caught&&fixture->references==1&&fixture->opens==1);checkCF();
                fixture->throwLookup=-1;assert([read(true) isEqualToString:@"fixture.legacy"]);checkCF();
                assert(fixture->opens==1&&fixture->closes==0);
            }
        }
    }
}
static void concurrentCases(){
    for(bool cold:{false,true}){
        reset();fixture->recordCalls=false;copyValues=@[[NSNull null],[NSNull null]];
        if(!cold)assert([read(true) isEqualToString:@"fixture.legacy"]);
        const unsigned before=fixture->legacyCalls;std::vector<std::thread> threads;
        for(unsigned worker=0;worker<8;++worker)threads.emplace_back([]{
            for(unsigned n=0;n<1000;++n){@autoreleasepool{assert([read(true) isEqualToString:@"fixture.legacy"]);}}
        });
        for(auto &thread:threads)thread.join();
        assert(fixture->legacyCalls==before+8000&&fixture->references==1&&fixture->closes+1==fixture->opens);
        if(!cold)assert(fixture->opens==1&&fixture->lookups==4);
        checkCF();
    }
}
static void deferredLookupCases(){
    for(bool current:{false,true}){
        reset();fixture->available[1]=false;fixture->recordCalls=false;
        for(unsigned n=0;n<10000;++n){@autoreleasepool{
            NSString *fresh=[NSString stringWithFormat:@"com.lazy.%u",n];copyValues=@[fresh,[NSNull null]];
            NSString *value=current?read(true):Preceding::TLinkAXFrontmostBundleID();
            assert([value isEqualToString:fresh]);
        }}
        assert(fixture->slotLookups[0]==1&&fixture->slotLookups[1]==(current?0U:10000U));
        assert(fixture->slotLookups[2]==0&&fixture->slotLookups[3]==0&&fixture->copyCalls[0]==10000&&fixture->copyCalls[1]==0);
        assert(fixture->opens==1&&fixture->references==1);checkCF();
    }
    for(id first in @[[NSNull null],@""]){
        @autoreleasepool{
            reset();fixture->available[1]=false;copyValues=@[first,@"second.live"];
            assert([read(true) isEqualToString:@"fixture.legacy"]&&fixture->slotLookups[1]==1);
            assert([read(true) isEqualToString:@"fixture.legacy"]&&fixture->slotLookups[1]==2);
            fixture->available[1]=true;assert([read(true) isEqualToString:@"second.live"]&&fixture->slotLookups[1]==3);
            copyValues=@[@"first.live",@"second.changed"];assert([read(true) isEqualToString:@"first.live"]&&fixture->slotLookups[1]==3);
            copyValues=@[first,@"second.changed"];assert([read(true) isEqualToString:@"second.changed"]&&fixture->slotLookups[1]==3);
            assert(fixture->opens==1&&fixture->references==1);checkCF();
        }
    }
    for(int kind=1;kind<=2;++kind){
        @autoreleasepool{
            reset();fixture->throwLookup=1;fixture->lookupFault=kind;
            assert([read(true) isEqualToString:@"fixture.first"]&&fixture->slotLookups[1]==0);
            copyValues=@[[NSNull null],@"after.lookup"];
            bool caught=false;
            @try{try{read(true);}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXFrontmostFixture"];}
            assert(caught&&fixture->slotLookups[1]==1&&fixture->references==1);checkCF();
            fixture->throwLookup=-1;assert([read(true) isEqualToString:@"after.lookup"]);checkCF();
        }
    }
}
int main(){@autoreleasepool{
    std::puts("AX foreground symbols Foundation: actual/frozen helper, controlled loader/private providers, real CF strings and Foundation copies");
    parityCases();warmAndLiveCases();retryAndLifetimeCases();exceptionCases();concurrentCases();deferredLookupCases();copyValues=nil;legacyBytes=nil;providerCalls=nil;
    std::puts("AX foreground lazy lookup passed: 10k first-provider successes with zero versus10k unused-secondary lookups, nil/empty fallback retry/recovery, fresh second values and secondary NS/C++ faults deferred until the branch is reached.");
    std::puts("AX foreground symbols passed: 256 frozen values/provider-order/CF cases, 10k fresh reads per route with one pinned handle, copy/legacy fallback, missing lookup recovery, mutable-input snapshots, NS/C++ unwind and 16k cold/warm concurrent reads. Foreground guards/PID policy unchanged; private framework/device qualification pending.");
}return 0;}
