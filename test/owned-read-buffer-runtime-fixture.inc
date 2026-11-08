#include "persistence-json-buffer-fixture.h"
namespace OwnedReadNativeFixture {
using PersistenceStorageFixture::Trace;
using TLinkPersistenceJSONStorage::Buffer;
enum class Mode {owned,copied,refused,wrongLength,objcFault,cppFault};
static Mode mode=Mode::owned;
static unsigned calls=0;
static std::weak_ptr<Buffer> ownerSeen;
static NSData * _Nullable factory(const std::shared_ptr<Buffer> &owner){
    ++calls;ownerSeen=owner;
    switch(mode){
        case Mode::owned:return TLinkOwnedReadCreateData(owner);
        case Mode::copied:return [NSData dataWithBytes:owner->data() length:owner->size()];
        case Mode::refused:return nil;
        case Mode::wrongLength:return [@"x" dataUsingEncoding:NSUTF8StringEncoding];
        case Mode::objcFault:[NSException raise:@"OwnedReadFixture" format:@"factory"];return nil;
        case Mode::cppFault:throw std::runtime_error("factory");
    }
    return nil;
}
static void cases(){
    puts("Owned read Foundation: actual reserved/committed storage, real NSData and caller-pool ownership");
    for(NSUInteger length:{NSUInteger(0),NSUInteger(1),NSUInteger(17),NSUInteger(65537)}){
        Trace trace;NSData *held=nil;std::vector<uint8_t> expected(length);
        for(NSUInteger n=0;n<length;++n)expected[n]=uint8_t(n*13+7);
        @autoreleasepool {
            TLinkOwnedReadBuffer *buffer=[[TLinkOwnedReadBuffer alloc] initWithLength:length allocator:trace.allocator()];
            assert(buffer&&buffer.length==length&&buffer.committedLength==0&&trace.requests==(length?1U:0U));
            if(length){
                assert(((uint8_t *)buffer.mutableBytes)[0]==0xa5&&![buffer takeData]);
                const NSUInteger half=length/2;
                uint8_t *bytes=(uint8_t *)buffer.mutableBytes;assert(bytes);
                if(half)memcpy(bytes,expected.data(),half);
                assert([buffer commitBytes:half]&&![buffer takeData]);
                memcpy(bytes+half,expected.data()+half,length-half);
                assert([buffer commitBytes:length-half]);
            }else assert([buffer commitBytes:0]);
            held=[buffer takeData];assert(held&&held.length==length&&buffer.committedLength==length);
            assert(!buffer.mutableBytes&&![buffer commitBytes:0]&&![buffer takeData]);
        }
        @autoreleasepool {
            if(length){assert(memcmp(held.bytes,expected.data(),length)==0);}
            held=nil;
        }
        assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;
        @autoreleasepool {
            TLinkOwnedReadBuffer *buffer=[[TLinkOwnedReadBuffer alloc] initWithLength:8 allocator:trace.allocator()];
            uint8_t *bytes=(uint8_t *)buffer.mutableBytes;assert(bytes);memset(bytes,0x71,8);assert([buffer commitBytes:7]&&![buffer takeData]);
            assert(![buffer commitBytes:2]&&!buffer.mutableBytes&&![buffer takeData]&&buffer.committedLength==7);
        }
        assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    for(Mode selected:{Mode::owned,Mode::copied,Mode::refused,Mode::wrongLength,Mode::objcFault,Mode::cppFault}){
        Trace trace;mode=selected;calls=0;ownerSeen.reset();
        @autoreleasepool {
            TLinkOwnedReadBuffer *buffer=[[TLinkOwnedReadBuffer alloc] initWithLength:3 allocator:trace.allocator()];
            uint8_t *bytes=(uint8_t *)buffer.mutableBytes;assert(bytes);memcpy(bytes,"[1]",3);assert([buffer commitBytes:3]);
            NSData *data=nil;bool ns=false,cpp=false;
            @try {try {data=[buffer takeData:factory];}catch(const std::runtime_error &){cpp=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"OwnedReadFixture"]);ns=true;}
            assert(calls==1&&ns==(selected==Mode::objcFault)&&cpp==(selected==Mode::cppFault));
            const bool success=selected==Mode::owned||selected==Mode::copied;
            assert((data!=nil)==success&&!buffer.mutableBytes&&![buffer takeData]);
            if(data)assert([data isEqual:[@"[1]" dataUsingEncoding:NSUTF8StringEncoding]]);
            data=nil;
        }
        assert(ownerSeen.expired()&&trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;trace.failRequest=1;
        @autoreleasepool {TLinkOwnedReadBuffer *buffer=[[TLinkOwnedReadBuffer alloc] initWithLength:64 allocator:trace.allocator()];assert(!buffer);}
        assert(trace.requests==1&&trace.blocks.empty());
    }
    puts("Owned read Foundation passed: poisoned uninitialized reserve, partial/overflow commit refusal, exact empty/direct-fill bytes, detached NSData after buffer retirement, real/copy/refused/short/NS/C++ factories and allocation denial; zero final blocks. Foundation/OS zeroing and device memory/latency remain unmeasured.");
}
}
