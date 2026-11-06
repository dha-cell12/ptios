static unsigned storageFactoryMode=0;
static std::weak_ptr<TLinkAXJSONOutput::Buffer> storageFactoryOwner;
static std::shared_ptr<TLinkNativeCancellation> storageCancellation;
static NSData *controlledStorageFactory(const std::shared_ptr<TLinkAXJSONOutput::Buffer> &owner){
    storageFactoryOwner=owner;assert(owner&&owner->size()==2);
    if(storageFactoryMode==1)return nil;
    if(storageFactoryMode==2)[NSException raise:@"JSONStorageFixture" format:@"factory"];
    if(storageFactoryMode==3)throw std::runtime_error("factory");
    if(storageFactoryMode==4)return [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data=TLinkAXJSONCreateData(owner);
    if(storageFactoryMode==5){assert(storageCancellation);storageCancellation->cancel();}
    return storageFactoryMode==6?nil:data;
}
struct StorageAllocationTrace {size_t live=0,releases=0,maximum=0;};
static void *storageResize(void *context,void *previous,size_t count){
    auto &trace=*static_cast<StorageAllocationTrace *>(context);
    assert(count&&count<=TLinkAXJSONOutput::MaxJSONBytes);trace.maximum=std::max(trace.maximum,count);
    void *next=std::realloc(previous,count);assert(next);
    if(!previous)++trace.live;
    return next;
}
static void storageFree(void *context,void *bytes){
    auto &trace=*static_cast<StorageAllocationTrace *>(context);assert(bytes&&trace.live==1);
    --trace.live;++trace.releases;std::free(bytes);
}
static void storageLifetimeCases(){
    using namespace TLinkAXJSONOutput;
    for(unsigned n=0;n<128;++n){
        StorageAllocationTrace trace;std::weak_ptr<Buffer> weak;NSData *held=nil;
        @autoreleasepool{
            auto owner=std::make_shared<Buffer>(Allocator(&trace,storageResize,storageFree));weak=owner;
            const uint8_t chunk[]={0,1,2,3,4,5,6,7};
            for(unsigned i=0;i<64;++i)assert(owner->append(chunk,sizeof(chunk)));
            assert(owner->seal());held=TLinkAXJSONCreateData(owner);assert(held&&held.length==512);
            assert(!owner->append(chunk,1));owner.reset();
        }
        assert(held.length==512);
        for(NSUInteger i=0;i<held.length;++i)assert(((const uint8_t *)held.bytes)[i]==i%8);
        @autoreleasepool{held=nil;}
        assert(weak.expired()&&trace.live==0&&trace.releases==1&&trace.maximum<=MaxJSONBytes);
    }
    NSData *held=nil;__weak TLinkAXJSONStream *weakStream=nil;
    @autoreleasepool{
        TLinkAXJSONStream *stream=[TLinkAXJSONStream new];weakStream=stream;[stream open];
        const uint8_t body[]={'{','}'};assert([stream write:body maxLength:2]==2);
        held=[stream takeData:TLinkAXJSONCreateData];assert(held&&![stream takeData:TLinkAXJSONCreateData]);
        assert([stream write:body maxLength:2]==-1);
        [stream close];[stream close];assert(stream.streamStatus==NSStreamStatusClosed);
    }
    assert(!weakStream&&[held isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);held=nil;
}
static void storageFactoryCases(){
    for(unsigned mode=0;mode<=6;++mode){
        __weak TLinkAXJSONStream *weakStream=nil;
        @autoreleasepool{
            storageFactoryMode=mode;storageCancellation=std::make_shared<TLinkNativeCancellation>();
            auto budget=std::make_shared<TLinkNativeBudget>(storageCancellation,0,1024);
            TLinkNativeBudgetScope scope(budget);BOOL large=YES,stopped=YES;NSData *data=nil;bool caught=false;
            jsonWriterMode=0;
            @try{try{data=TLinkAXJSONDataWithWriter(@{},&large,controlledJSONWriter,&stopped,controlledStorageFactory);}
                catch(const std::runtime_error &){caught=mode==3;}}
            @catch(NSException *exception){caught=mode==2&&[exception.name isEqualToString:@"JSONStorageFixture"];}
            assert(caught==(mode==2||mode==3));
            assert(heldJSONStream.streamStatus==NSStreamStatusClosed&&heldJSONStream.byteCount==2);
            assert(!large&&stopped==(mode==5));
            if(mode==0)assert([data isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);
            else assert(!data);
            weakStream=heldJSONStream;heldJSONStream=nil;storageCancellation.reset();
        }
        assert(!weakStream&&storageFactoryOwner.expired()&&!TLinkCurrentNativeBudget());
    }
    storageFactoryOwner.reset();
}
static void storageCodecCases(){
    for(bool root:{false,true})for(bool capability:{false,true}){
        for(unsigned n=0;n<64;++n){
            NSDictionary *expected=nil;
            for(bool current:{false,true}){@autoreleasepool{
                reset();useBeforeStorageJSON=!current;
                NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀\n\"\\",@"n":@(n),@"nested":@[@{},@[@1,[NSNull null]] ]};
                fixtureCapability=graph;NSDictionary *value=decoded(call(root,capability,true,graph));
                if(current)assert([value isEqual:expected]);else expected=value;
                assert(jsonCalls==1&&base64Calls==1&&lastJSON.length<=TLinkAXJSONOutput::MaxJSONBytes);
            }}
        }
    }
    reset();
}
static void jsonStorageCases(){
    std::puts("AX JSON ownership: actual NSData deallocator, sealed raw storage, factory faults and C05v codec parity");
    storageLifetimeCases();storageFactoryCases();storageCodecCases();
    std::puts("AX JSON ownership passed: 128 traced allocation/NSData/pool retirements, sealed publication, nil/wrong-length/NS-C++ factory failures, post-adoption cancellation and four frozen C05v graph routes. Foundation internals/device RSS remain unqualified.");
}
