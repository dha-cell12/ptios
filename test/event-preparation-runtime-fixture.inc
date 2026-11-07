static thread_local bool fixtureForceCountFallback=false,fixtureCountOwners=false;
static thread_local unsigned fixtureDefaultWriterFault=0;
static thread_local NSUInteger fixtureFallbackPayloadCalls=0,fixtureLegacyPayloadCalls=0;
static unsigned fixtureCountWriterMode=0;
static NSOutputStream *fixtureHeldCountStream;
static __weak NSOutputStream *fixtureWeakCountStream;
static const uint8_t *fixtureEventNullBytes(){return nullptr;}
static NSInteger FixtureEventDefaultCountWrite(id object,NSOutputStream *stream,NSError *__autoreleasing *error){
    if(fixtureCountOwners)TLinkAXFixtureAutoreleaseOwner();
    if(fixtureDefaultWriterFault==1){if(error)*error=[NSError errorWithDomain:@"CounterFixture" code:1 userInfo:nil];return 0;}
    if(fixtureDefaultWriterFault==2)[NSException raise:@"CounterFixture" format:@"default writer"];
    if(fixtureDefaultWriterFault==3)throw std::runtime_error("default writer");
    return [NSJSONSerialization writeJSONObject:object toStream:stream options:0 error:error];
}
static BOOL FixtureEventEncodedSize(id object,NSUInteger *size){return fixtureForceCountFallback?NO:TLinkEventJSONEncodedSize(object,size);}
static NSData *FixtureEventFallbackPayloadData(id object){++fixtureFallbackPayloadCalls;return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];}
static NSData *FixtureEventLegacyPayloadData(id object){++fixtureLegacyPayloadCalls;return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];}
static NSInteger fixtureEventCountWriter(id object,NSOutputStream *stream,NSError *__autoreleasing *error){
    (void)object;fixtureHeldCountStream=stream;fixtureWeakCountStream=stream;
    if(fixtureCountOwners)TLinkAXFixtureAutoreleaseOwner();
    const uint8_t bytes[]={'a','b'};
    if(fixtureCountWriterMode==0){assert([stream write:bytes maxLength:1]==1);assert([stream write:bytes+1 maxLength:1]==1);return 2;}
    if(fixtureCountWriterMode==1)return 0;
    if(fixtureCountWriterMode==2)return -1;
    assert([stream write:bytes maxLength:2]==2);
    if(fixtureCountWriterMode==3)return 1;
    if(fixtureCountWriterMode==4){if(error)*error=[NSError errorWithDomain:@"CounterFixture" code:7 userInfo:nil];return 2;}
    if(fixtureCountWriterMode==5){[stream close];return 2;}
    if(fixtureCountWriterMode==6){assert([stream write:fixtureEventNullBytes() maxLength:1]==-1);return 2;}
    if(fixtureCountWriterMode==7)[NSException raise:@"CounterFixture" format:@"writer"];
    throw std::runtime_error("writer");
}
static void fixtureEventCounterCases(){
    for(unsigned mode=0;mode<=8;++mode){
        NSUInteger size=777;BOOL ok=NO;bool threw=false;
        fixtureCountWriterMode=mode;fixtureCountOwners=true;TLinkAXFixtureResetOwners();
        @autoreleasepool {
            @try {try {ok=TLinkEventJSONCountWithWriter(@{},&size,fixtureEventCountWriter);}catch(const std::runtime_error &){threw=true;}}
            @catch(NSException *caught){assert([caught.name isEqual:@"CounterFixture"]);threw=true;}
            assert(fixtureHeldCountStream.streamStatus==NSStreamStatusClosed);
            assert(threw==(mode>=7)&&ok==(mode==0)&&size==(mode==0?2U:777U));
            if(mode<7)assert(TLinkAXFixtureLiveOwners()==0);
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
        fixtureHeldCountStream=nil;assert(fixtureWeakCountStream==nil);fixtureCountOwners=false;
    }
    NSUInteger refused=123;
    assert(!TLinkEventJSONCountWithWriter(@{},NULL,fixtureEventCountWriter));
    assert(!TLinkEventJSONCountWithWriter(@{},&refused,nullptr)&&refused==123);
    TLinkEventJSONCountStream *stream=[TLinkEventJSONCountStream new];const uint8_t byte=1;
    assert(!stream.hasSpaceAvailable&&[stream write:&byte maxLength:1]==-1);[stream close];
    stream=[TLinkEventJSONCountStream new];[stream open];
    assert([stream write:fixtureEventNullBytes() maxLength:0]==0&&stream.byteCount==0);
    assert([stream write:&byte maxLength:1]==1&&stream.byteCount==1);[stream close];
    assert(!stream.hasSpaceAvailable&&[stream write:&byte maxLength:1]==-1);[stream close];
}
static void fixtureEventPayloadCases(){
    NSArray *texts=@[@"",@"ảnh 测试 😀\0tail",@"quote\"slash/\\\n\r\t",@"\u2028\u2029"];
    NSMutableArray *payloads=[NSMutableArray arrayWithArray:@[@{},@{@"null":[NSNull null],@"bool":@YES,@"number":@(UINT64_MAX)},@{@"bad":@(NAN)}]];
    for(NSString *text in texts)[payloads addObject:@{@"text":text,@"nested":@[@1,@NO,@{@"text":text}]}];
    const NSUInteger overhead=[NSJSONSerialization dataWithJSONObject:@{@"text":@""} options:0 error:nil].length;
    for(NSUInteger bytes:{kTLinkEventPayloadMaxBytes-1,kTLinkEventPayloadMaxBytes,kTLinkEventPayloadMaxBytes+1,NSUInteger(1024*1024)}){
        assert(bytes>overhead);
        NSDictionary *payload=@{@"text":[@"x" stringByPaddingToLength:bytes-overhead withString:@"x" startingAtIndex:0]};
        assert([NSJSONSerialization dataWithJSONObject:payload options:0 error:nil].length==bytes);[payloads addObject:payload];
    }
    for(unsigned fault=1;fault<=3;++fault){
        @autoreleasepool {
            NSDictionary *payload=@{@"text":@"ảnh"};NSDictionary *expected=FixtureBeforeBoundedPayload(payload);
            TLinkAXFixtureResetOwners();fixtureCountOwners=true;fixtureDefaultWriterFault=fault;fixtureFallbackPayloadCalls=0;
            NSDictionary *actual=TLinkEventBoundedPayload(payload);fixtureDefaultWriterFault=0;fixtureCountOwners=false;
            assert([actual isEqual:expected]&&fixtureFallbackPayloadCalls==1&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
        }
    }
    for(unsigned n=0;n<256;++n)[payloads addObject:@{@"n":@(n),@"text":texts[n%texts.count],@"array":@[@(n),@{@"inside":@"ảnh"}]}];
    for(id payload in payloads){
        @autoreleasepool {
            const BOOL valid=[NSJSONSerialization isValidJSONObject:payload];
            NSUInteger encodedBytes=0;
            if(valid){NSUInteger counted=0;encodedBytes=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil].length;assert(TLinkEventJSONEncodedSize(payload,&counted));assert(counted==encodedBytes);}
            fixtureLegacyPayloadCalls=fixtureFallbackPayloadCalls=0;
            NSDictionary *expected=FixtureBeforeBoundedPayload(payload),*actual=TLinkEventBoundedPayload(payload);
            assert([expected isEqual:actual]&&fixtureLegacyPayloadCalls==(valid?1U:0U)&&fixtureFallbackPayloadCalls==0);
            if(valid&&encodedBytes>kTLinkEventPayloadMaxBytes)assert([expected[@"original_bytes"] isEqual:actual[@"original_bytes"]]);
            else if(valid)assert(actual==payload);
            fixtureForceCountFallback=true;fixtureFallbackPayloadCalls=0;
            NSDictionary *fallback=TLinkEventBoundedPayload(payload);fixtureForceCountFallback=false;
            assert([expected isEqual:fallback]&&fixtureFallbackPayloadCalls==(valid?1U:0U));
        }
    }
}
static thread_local NSUInteger fixtureSequenceReads=0;
@interface FixtureEventSequenceProbe : NSObject
@property(nonatomic) uint64_t value;
- (unsigned long long)unsignedLongLongValue;
@end
@implementation FixtureEventSequenceProbe
- (unsigned long long)unsignedLongLongValue {++fixtureSequenceReads;return self.value;}
@end
@interface FixtureEventTopicsProbe : NSObject {
@public NSSet *values;NSUInteger counts,contains;
}
@property(nonatomic,readonly) NSUInteger count;
- (BOOL)containsObject:(id)object;
@end
@implementation FixtureEventTopicsProbe
- (NSUInteger)count {++counts;return values.count;}
- (BOOL)containsObject:(id)object {++contains;return [values containsObject:object];}
@end
static void fixtureEventBatchWork(){
    NSMutableArray *events=[NSMutableArray array];
    for(unsigned n=1;n<=256;++n){FixtureEventSequenceProbe *sequence=[FixtureEventSequenceProbe new];sequence.value=n;[events addObject:@{@"sequence":sequence,@"topic":@"a"}];}
    NSDictionary *journal=@{@"events":events,@"next_sequence":@257};
    for(uint64_t cursor:{uint64_t(0),uint64_t(256)}){
        FixtureEventTopicsProbe *oldTopics=[FixtureEventTopicsProbe new],*nowTopics=[FixtureEventTopicsProbe new];
        oldTopics->values=nowTopics->values=[NSSet setWithObject:@"*"];
        fixtureSequenceReads=0;NSDictionary *old=FixtureBeforeEventBatch(journal,cursor,(NSSet *)oldTopics,32,NO);
        const NSUInteger oldReads=fixtureSequenceReads;
        fixtureSequenceReads=0;NSDictionary *now=TLinkEventBatchFromJournal(journal,cursor,(NSSet *)nowTopics,32,NO);
        assert([old isEqual:now]);
        if(cursor==256)assert(oldReads==257&&fixtureSequenceReads==2&&oldTopics->contains==256&&nowTopics->contains==0&&nowTopics->counts==0);
        else assert(oldReads==34&&fixtureSequenceReads==34&&oldTopics->contains==33&&nowTopics->contains==1&&nowTopics->counts==1);
    }
}
static void fixtureEventBatchCases(){
    for(unsigned trial=0;trial<128;++trial){
        @autoreleasepool {
            NSMutableArray *events=[NSMutableArray array];
            const unsigned count=trial%3?256:trial;uint64_t sequence=trial*3+1;
            for(unsigned n=0;n<count;++n){[events addObject:@{@"sequence":@(sequence),@"topic":n%2?@"a":@"b"}];sequence+=1+trial%2;}
            NSDictionary *journal=@{@"events":events,@"next_sequence":@(sequence)};
            for(uint64_t cursor:{uint64_t(0),uint64_t(1),uint64_t(127),sequence-1,sequence,UINT64_MAX}){
                for(NSUInteger limit:{NSUInteger(0),NSUInteger(1),NSUInteger(16),NSUInteger(32),NSUIntegerMax}){
                    for(NSSet *topics in @[[NSSet set],[NSSet setWithObject:@"*"],[NSSet setWithObject:@"a"],[NSSet setWithObject:@"missing"]]){
                        NSDictionary *old=FixtureBeforeEventBatch(journal,cursor,topics,limit,NO),*now=TLinkEventBatchFromJournal(journal,cursor,topics,limit,NO);
                        assert([old isEqual:now]);
                        for(NSUInteger n=0;n<[old[@"events"] count];++n)assert(old[@"events"][n]==now[@"events"][n]);
                    }
                }
            }
        }
    }
}
static void fixtureEventPreparationCases(){
    puts("Event preparation Foundation: real JSON stream/data counts, legacy payload fallback and current/frozen ordered batch graphs");fflush(stdout);
    fixtureEventCounterCases();fixtureEventPayloadCases();fixtureEventBatchCases();fixtureEventBatchWork();
    assert(!fixtureForceCountFallback&&!fixtureCountOwners&&fixtureHeldCountStream==nil);
    puts("Event preparation Foundation passed: real Unicode/NUL/numeric/nested/large JSON byte parity, zero explicit full encoder calls on coherent count path, exact payload identity/truncation and forced original fallback; stream zero/error/mismatch/close/NS/C++ cleanup; 15360 frozen batch graphs and event identities. Foundation internals and device gains remain unqualified.");
}
