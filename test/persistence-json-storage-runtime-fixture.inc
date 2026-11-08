#include "persistence-json-buffer-fixture.h"
namespace PersistenceStorageNativeFixture {
using PersistenceStorageFixture::Trace;
using TLinkPersistenceJSONStorage::Buffer;
enum class FactoryMode {owned,copied,refused,wrongLength,objcFault,cppFault};
static FactoryMode mode=FactoryMode::owned;
static unsigned factoryCalls=0;
static std::weak_ptr<Buffer> observedOwner;
static NSData * _Nullable factory(const std::shared_ptr<Buffer> &owner){
    ++factoryCalls;observedOwner=owner;
    switch(mode){
        case FactoryMode::owned:return TLinkPersistenceJSONCreateData(owner);
        case FactoryMode::copied:return [NSData dataWithBytes:owner->data() length:owner->size()];
        case FactoryMode::refused:return nil;
        case FactoryMode::wrongLength:return [@"x" dataUsingEncoding:NSUTF8StringEncoding];
        case FactoryMode::objcFault:[NSException raise:@"PersistenceStorageFixture" format:@"data factory"];return nil;
        case FactoryMode::cppFault:throw std::runtime_error("data factory");
    }
    return nil;
}
static void cases(){
    puts("Persistence storage Foundation: complete C03aq/current streams, real JSON and NSData ownership/factory faults");
    for(unsigned cycle=0;cycle<64;++cycle){@autoreleasepool {
        NSDictionary *object=@{@"payload":@[@(cycle),@"ảnh\0测试😀",@[@YES,[NSNull null]],@{@"n":@(-0.25)}]};
        const NSJSONWritingOptions options[]={0,NSJSONWritingPrettyPrinted,NSJSONWritingSortedKeys};
        for(NSJSONWritingOptions option:options){
            NSData *encoded=[NSJSONSerialization dataWithJSONObject:object options:option error:nil];assert(encoded.length>0);
            const NSUInteger caps[]={encoded.length-1,encoded.length,encoded.length+1};
            for(NSUInteger cap:caps){
                NSData *before=BeforeStorageTLinkPersistenceJSONData(object,option,cap);
                NSData *now=TLinkPersistenceJSONData(object,option,cap);
                assert((!before&&!now)||[before isEqual:now]);
                if(now)assert([[NSJSONSerialization JSONObjectWithData:now options:0 error:nil] isEqual:object]);
            }
        }
    }}
    PersistenceJSONFixture::mode=PersistenceJSONFixture::Mode::Good;
    for(FactoryMode selected:{FactoryMode::owned,FactoryMode::copied,FactoryMode::refused,FactoryMode::wrongLength,FactoryMode::objcFault,FactoryMode::cppFault}){
        Trace trace;mode=selected;factoryCalls=0;observedOwner.reset();
        @autoreleasepool {
            NSData *result=nil;bool objcThrown=false,cppThrown=false;
            @try {try {result=TLinkPersistenceJSONWithWriter(@[],0,4096,PersistenceJSONFixture::writer,factory,trace.allocator());}
                catch(const std::runtime_error &){cppThrown=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"PersistenceStorageFixture"]);objcThrown=true;}
            const bool success=selected==FactoryMode::owned||selected==FactoryMode::copied;
            assert((result!=nil)==success&&factoryCalls==1&&trace.maximum<=4096);
            assert(objcThrown==(selected==FactoryMode::objcFault)&&cppThrown==(selected==FactoryMode::cppFault));
            TLinkPersistenceJSONStream *stream=(TLinkPersistenceJSONStream *)PersistenceJSONFixture::held;
            assert(stream.streamStatus==NSStreamStatusClosed&&stream.retainedCapacity==0);
            if(result){
                [stream close];assert([result isEqual:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]]);
                assert(![stream takeData]&&[result length]==2);
            }
            result=nil;PersistenceJSONFixture::held=nil;
        }
        // Inspect after a normal caller-pool drain; do not require early ARC destruction.
        assert(observedOwner.expired()&&trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    for(unsigned failure=0;failure<3;++failure){
        Trace trace;factoryCalls=0;mode=FactoryMode::owned;
        if(failure==0)trace.failRequest=1;
        if(failure==1)trace.throwNext=true;
        @autoreleasepool {
            NSData *result=nil;bool caught=false;
            @try {try {result=TLinkPersistenceJSONWithWriter(@[],0,failure==2?1:4096,PersistenceJSONFixture::writer,factory,trace.allocator());}
                catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){(void)exception;assert(false);}
            assert(!result&&caught==(failure==1)&&factoryCalls==0);
            if(failure==2)assert(trace.requests==0); // Quota rejects before allocator entry.
            PersistenceJSONFixture::held=nil;
        }
        assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    // A held stream does not retain the published allocation; NSData alone owns it.
    Trace trace;NSData *held=nil;
    @autoreleasepool {
        held=TLinkPersistenceJSONWithWriter(@[],0,4096,PersistenceJSONFixture::writer,TLinkPersistenceJSONCreateData,trace.allocator());
        assert(held&&[(TLinkPersistenceJSONStream *)PersistenceJSONFixture::held retainedCapacity]==0);
    }
    @autoreleasepool {assert([held isEqual:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]]);held=nil;}
    assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    PersistenceJSONFixture::held=nil;observedOwner.reset();
    puts("Persistence storage Foundation passed: 576 complete preceding/current JSON/option/quota cases, real NSData deallocator and copied fallback, nil/short/NS/C++ factories, allocation refusal/unwind, no allocation after quota refusal and detached cross-pool data with zero final blocks. Foundation allocation/RSS/device gains remain unmeasured.");
}
}
