static unsigned storageFactoryMode=0;
static const char *storagePhase="setup";
static unsigned storageIteration=0;
static void storageCheck(bool condition,const char *expression,int line){
    if(condition)return;
    std::fprintf(stderr,"AX JSON ownership failure: phase=%s iteration=%u factory=%u line=%d condition=%s\n",
        storagePhase,storageIteration,storageFactoryMode,line,expression);
    std::fflush(stderr);std::abort();
}
#define STORAGE_CHECK(...) storageCheck(static_cast<bool>((__VA_ARGS__)),#__VA_ARGS__,__LINE__)
static std::weak_ptr<TLinkAXJSONOutput::Buffer> storageFactoryOwner;
static std::shared_ptr<TLinkNativeCancellation> storageCancellation;
static NSData *controlledStorageFactory(const std::shared_ptr<TLinkAXJSONOutput::Buffer> &owner){
    storageFactoryOwner=owner;STORAGE_CHECK(owner&&owner->size()==2);
    if(storageFactoryMode==1)return nil;
    if(storageFactoryMode==2)[NSException raise:@"JSONStorageFixture" format:@"factory"];
    if(storageFactoryMode==3)throw std::runtime_error("factory");
    if(storageFactoryMode==4)return [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data=TLinkAXJSONCreateData(owner);
    if(storageFactoryMode==5){STORAGE_CHECK(storageCancellation);storageCancellation->cancel();}
    return storageFactoryMode==6?nil:data;
}
struct StorageAllocationTrace {size_t live=0,releases=0,maximum=0;};
static void *storageResize(void *context,void *previous,size_t count){
    auto &trace=*static_cast<StorageAllocationTrace *>(context);
    STORAGE_CHECK(count&&count<=TLinkAXJSONOutput::MaxJSONBytes);trace.maximum=std::max(trace.maximum,count);
    void *next=std::realloc(previous,count);STORAGE_CHECK(next);
    if(!previous)++trace.live;
    return next;
}
static void storageFree(void *context,void *bytes){
    auto &trace=*static_cast<StorageAllocationTrace *>(context);STORAGE_CHECK(bytes&&trace.live==1);
    --trace.live;++trace.releases;std::free(bytes);
}
static void storageLifetimeCases(){
    using namespace TLinkAXJSONOutput;
    storagePhase="traced NSData lifetime";
    std::fprintf(stderr,"AX JSON ownership: traced NSData lifetime begin\n");
    for(unsigned n=0;n<128;++n){
        storageIteration=n;
        StorageAllocationTrace trace;std::weak_ptr<Buffer> weak;
        @autoreleasepool{
          NSData *held=nil;
          @autoreleasepool{
            auto owner=std::make_shared<Buffer>(Allocator(&trace,storageResize,storageFree));weak=owner;
            const uint8_t chunk[]={0,1,2,3,4,5,6,7};
            for(unsigned i=0;i<64;++i)STORAGE_CHECK(owner->append(chunk,sizeof(chunk)));
            STORAGE_CHECK(owner->seal());held=TLinkAXJSONCreateData(owner);STORAGE_CHECK(held&&held.length==512);
            STORAGE_CHECK(!owner->append(chunk,1));owner.reset();
          }
          STORAGE_CHECK(held.length==512);
          for(NSUInteger i=0;i<held.length;++i)STORAGE_CHECK(((const uint8_t *)held.bytes)[i]==i%8);
          // Explicit MRC retain/autorelease models the permitted owner extension
          // of an inner-pointer read even when ARC optimizes its own retain away.
          TLinkAXFixtureHoldUntilPoolDrains(held);
          held=nil;
        }
        // Observe retirement only after the normal pool enclosing production,
        // cross-inner-pool reads and final NSData/block release has drained.
        const bool retired=weak.expired()&&trace.live==0&&trace.releases==1&&trace.maximum<=MaxJSONBytes;
        if(!retired)std::fprintf(stderr,"AX JSON ownership storage: expired=%d live=%zu frees=%zu max=%zu limit=%zu\n",
            weak.expired(),trace.live,trace.releases,trace.maximum,MaxJSONBytes);
        STORAGE_CHECK(retired);
    }
    storagePhase="sealed stream publication";storageIteration=0;
    std::fprintf(stderr,"AX JSON ownership: traced NSData lifetime passed; sealed stream begin\n");
    NSData *held=nil;__weak TLinkAXJSONStream *weakStream=nil;
    @autoreleasepool{
        TLinkAXJSONStream *stream=[TLinkAXJSONStream new];weakStream=stream;[stream open];
        const uint8_t body[]={'{','}'};STORAGE_CHECK([stream write:body maxLength:2]==2);
        held=[stream takeData:TLinkAXJSONCreateData];STORAGE_CHECK(held&&![stream takeData:TLinkAXJSONCreateData]);
        STORAGE_CHECK([stream write:body maxLength:2]==-1);
        [stream close];[stream close];STORAGE_CHECK(stream.streamStatus==NSStreamStatusClosed);
    }
    STORAGE_CHECK(!weakStream&&[held isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);held=nil;
}
static void storageFactoryCases(){
    storagePhase="factory failure/retirement";storageIteration=0;
    for(unsigned mode=0;mode<=6;++mode){
        std::fprintf(stderr,"AX JSON ownership: factory mode=%u begin\n",mode);
        __weak TLinkAXJSONStream *weakStream=nil;
        @autoreleasepool{
            storageFactoryMode=mode;storageCancellation=std::make_shared<TLinkNativeCancellation>();
            auto budget=std::make_shared<TLinkNativeBudget>(storageCancellation,0,1024);
            TLinkNativeBudgetScope scope(budget);BOOL large=YES,stopped=YES;NSData *data=nil;bool caught=false;
            jsonWriterMode=0;
            @try{try{data=TLinkAXJSONDataWithWriter(@{},&large,controlledJSONWriter,&stopped,controlledStorageFactory);}
                catch(const std::runtime_error &){caught=mode==3;}}
            @catch(NSException *exception){caught=mode==2&&[exception.name isEqualToString:@"JSONStorageFixture"];}
            STORAGE_CHECK(caught==(mode==2||mode==3));
            STORAGE_CHECK(heldJSONStream.streamStatus==NSStreamStatusClosed&&heldJSONStream.byteCount==2);
            STORAGE_CHECK(!large&&stopped==(mode==5));
            if(mode==0)STORAGE_CHECK([data isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);
            else STORAGE_CHECK(!data);
            weakStream=heldJSONStream;heldJSONStream=nil;storageCancellation.reset();
        }
        if(weakStream||!storageFactoryOwner.expired()||TLinkCurrentNativeBudget())
            std::fprintf(stderr,"AX JSON ownership retirement: factory=%u stream=%d storage=%d budget=%d\n",mode,
                weakStream!=nil,!storageFactoryOwner.expired(),TLinkCurrentNativeBudget()!=nullptr);
        STORAGE_CHECK(!weakStream&&storageFactoryOwner.expired()&&!TLinkCurrentNativeBudget());
    }
    storageFactoryOwner.reset();
}
static void storageCodecCases(){
    storagePhase="four-codec parity";storageIteration=0;
    std::fprintf(stderr,"AX JSON ownership: factory modes passed; codec parity begin\n");
    for(bool root:{false,true})for(bool capability:{false,true}){
        for(unsigned n=0;n<64;++n){
            storageIteration=n;
            NSDictionary *expected=nil;
            for(bool current:{false,true}){@autoreleasepool{
                reset();useBeforeStorageJSON=!current;
                NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀\n\"\\",@"n":@(n),@"nested":@[@{},@[@1,[NSNull null]] ]};
                fixtureCapability=graph;NSDictionary *value=decoded(call(root,capability,true,graph));
                if(current)STORAGE_CHECK([value isEqual:expected]);else expected=value;
                STORAGE_CHECK(jsonCalls==1&&base64Calls==1&&lastJSON.length<=TLinkAXJSONOutput::MaxJSONBytes);
            }}
        }
    }
    reset();
}
#undef STORAGE_CHECK
static void jsonStorageCases(){
    std::puts("AX JSON ownership: actual NSData deallocator, sealed raw storage, factory faults and C05v codec parity");
    storageLifetimeCases();storageFactoryCases();storageCodecCases();
    std::puts("AX JSON ownership passed: 128 traced allocation/NSData/pool retirements, sealed publication, nil/wrong-length/NS-C++ factory failures, post-adoption cancellation and four frozen C05v graph routes. Foundation internals/device RSS remain unqualified.");
}
