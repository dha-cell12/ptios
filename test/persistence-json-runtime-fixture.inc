// Compiled with the complete production implementation at global scope.
// Fault injection widens the buffer contract only at this test call site.
// Keep production NSOutputStream's nonnull API and its defensive checks intact.
@protocol TLinkPersistenceJSONFaultWriter <NSObject>
- (NSInteger)write:(const uint8_t * _Nullable)bytes maxLength:(NSUInteger)length;
@end
namespace PersistenceJSONFixture {
enum class Mode {Good,Error,Zero,Negative,Mismatch,IgnoredRefusal,Closed,ThrowNS,ThrowCPP};
static Mode mode=Mode::Good;
static NSOutputStream * _Nullable held;
static NSInteger writer(id _Nullable object,NSOutputStream * _Nonnull stream,NSJSONWritingOptions options,
                        NSError * _Nullable __autoreleasing * _Nonnull error){
    (void)object;(void)options;held=stream;
    const uint8_t bytes[]={'[',']'};
    const NSInteger written=[stream write:bytes maxLength:sizeof(bytes)];
    switch(mode){
        case Mode::Good:return written;
        case Mode::Error:*error=[NSError errorWithDomain:@"fixture" code:1 userInfo:nil];return written;
        case Mode::Zero:return 0;
        case Mode::Negative:return -1;
        case Mode::Mismatch:return written+1;
        case Mode::IgnoredRefusal:return 2;
        case Mode::Closed:[stream close];return written;
        case Mode::ThrowNS:@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
        case Mode::ThrowCPP:throw std::runtime_error("fixture");
    }
    return -1;
}
static void cases(){
    puts("Persistence JSON Foundation: actual quota stream, real serializer, writer faults and detached buffer lifetime");
    // Sorted bytes are deterministic; ordinary and pretty output retain graphs.
    for(unsigned n=0;n<128;++n){@autoreleasepool {
        NSDictionary *object=@{@"id":@(n),@"text":@"ảnh;测试\0\n",@"rows":@[@1,@YES,[NSNull null],@{@"x":@1.25}]};
        const NSJSONWritingOptions modes[]={0,NSJSONWritingPrettyPrinted,NSJSONWritingSortedKeys};
        for(NSJSONWritingOptions options:modes){
            NSData *before=[NSJSONSerialization dataWithJSONObject:object options:options error:nil];assert(before.length>0);
            NSData *now=TLinkPersistenceJSONData(object,options,before.length);
            assert(now&&now.length==before.length);
            assert([[NSJSONSerialization JSONObjectWithData:now options:0 error:nil] isEqual:object]);
            if(options==NSJSONWritingSortedKeys)assert([before isEqual:now]);
            assert(!TLinkPersistenceJSONData(object,options,before.length-1));
            assert(TLinkPersistenceJSONData(object,options,before.length+1));
        }
    }}
    assert(!TLinkPersistenceJSONData(@[],0,0));
    assert(!TLinkPersistenceJSONWithWriter(@[],0,2,nullptr));
    for(Mode test:{Mode::Good,Mode::Error,Mode::Zero,Mode::Negative,Mode::Mismatch,Mode::Closed,Mode::ThrowNS,Mode::ThrowCPP}){
        mode=test;BOOL nsThrown=NO;bool cppThrown=false;NSData *result=nil;
        @try {try {result=TLinkPersistenceJSONWithWriter(@[],0,2,writer);}catch(const std::runtime_error &){cppThrown=true;}}
        @catch(NSException *exception){(void)exception;nsThrown=YES;}
        assert(nsThrown==(test==Mode::ThrowNS)&&cppThrown==(test==Mode::ThrowCPP));
        assert((result!=nil)==(test==Mode::Good));assert(held.streamStatus==NSStreamStatusClosed);
        // Rejected prefixes are retired even if an encoder retains the stream.
        assert([held valueForKey:@"_data"]==nil);
        if(result){
            NSData *snapshot=[result copy];const uint8_t extra='x';
            [held open];assert([held write:&extra maxLength:1]==-1);assert([result isEqual:snapshot]);
        }
        held=nil;
    }
    mode=Mode::Good;assert(!TLinkPersistenceJSONWithWriter(@[],0,1,writer));held=nil;
    mode=Mode::IgnoredRefusal;assert(!TLinkPersistenceJSONWithWriter(@[],0,1,writer));held=nil;
    TLinkPersistenceJSONStream *invalid=[[TLinkPersistenceJSONStream alloc] initWithLimit:16];[invalid open];
    id<TLinkPersistenceJSONFaultWriter> faultWriter=(id<TLinkPersistenceJSONFaultWriter>)invalid;
    assert([faultWriter write:nullptr maxLength:0]==0&&invalid.byteCount==0);
    assert([faultWriter write:nullptr maxLength:1]==-1&&invalid.failed&&invalid.byteCount==0);[invalid close];
    // Both production quotas refuse a whole incoming chunk before copying it.
    for(NSUInteger cap:{(NSUInteger)(4U*1024U*1024U),(NSUInteger)(32U*1024U*1024U)}){
        TLinkPersistenceJSONStream *stream=[[TLinkPersistenceJSONStream alloc] initWithLimit:cap];[stream open];
        const uint8_t byte='x';assert([stream write:&byte maxLength:1]==1);
        assert([stream write:&byte maxLength:cap]==-1&&stream.byteCount==1&&stream.failed);
        assert(![stream takeData]);[stream close];assert([stream valueForKey:@"_data"]==nil);
    }
    NSData *survivor=nil;
    @autoreleasepool {survivor=TLinkPersistenceJSONData(@[@"Unicode 测试",@42],NSJSONWritingSortedKeys,4096);}
    assert(([NSJSONSerialization JSONObjectWithData:survivor options:0 error:nil]));
    puts("Persistence JSON Foundation passed: 128 real Unicode/NUL/nested graph cases, exact/short quotas, deterministic sorted bytes, incoherent/error/closed writers, NS/C++ unwind, rejected-prefix retirement and cross-pool/detached output. Atomic writes remain in callers; device allocation/RSS qualification pending.");
}
}
