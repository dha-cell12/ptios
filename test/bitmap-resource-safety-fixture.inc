static std::atomic<unsigned> bitmapRefs{0},bitmapMakes{0},bitmapDrops{0},bitmapAllocations{0},bitmapFrees{0};
static int *bitmapMake(){++bitmapMakes;++bitmapRefs;return new int(42);}
static void bitmapDrop(int *value){assert(value&&*value==42);delete value;++bitmapDrops;--bitmapRefs;}
static void *bitmapAllocate(size_t count,size_t size){void *value=std::calloc(count,size);if(value)++bitmapAllocations;return value;}
static void bitmapFree(void *value){assert(value);std::free(value);++bitmapFrees;}
static void *bitmapFailAllocate(size_t count,size_t size){(void)count;(void)size;return nullptr;}
static void bitmapResourceCases(){
    using namespace TLinkBitmapCore;
    for(unsigned race=0;race<32;++race){
        {Memo<int *> memo(bitmapDrop);std::vector<std::thread> threads;
            for(unsigned t=0;t<8;++t)threads.emplace_back([&]{for(unsigned n=0;n<10000;++n){assert(*memo.get(bitmapMake)==42);}});
            for(auto &thread:threads){thread.join();}
            assert(bitmapRefs==1);
        }assert(bitmapRefs==0&&bitmapMakes==bitmapDrops);
    }
    {Memo<int *> memo(bitmapDrop);assert(!memo.get([]()->int *{return nullptr;}));bool caught=false;
        try{memo.get([]()->int *{throw std::runtime_error("color space");});}catch(const std::runtime_error &){caught=true;}
        assert(caught);assert(memo.get(bitmapMake));
    }assert(bitmapRefs==0);
    {Memo<int *> memo(bitmapDrop);int *published=memo.get([&]{assert(memo.get(bitmapMake));return bitmapMake();});assert(published&&bitmapRefs==1);}
    {Memo<int *> memo(bitmapDrop);assert(memo.get([&]()->int *{assert(memo.get(bitmapMake));return nullptr;}));}
    assert(bitmapRefs==0&&bitmapMakes==bitmapDrops);
    for(unsigned n=0;n<100000;++n){
        const size_t size=1+n%128;
        auto owner=Bytes::Allocate(size,bitmapAllocate,bitmapFree);assert(owner&&owner->size()==size&&owner->data());
        const uint8_t *bytes=(const uint8_t *)owner->data();for(size_t i=0;i<size;++i){assert(bytes[i]==0);}
        auto dataLease=owner;owner->markDataRelease();assert(owner->dataReleased()&&owner->data());owner.reset();assert(dataLease->data());dataLease.reset();
        assert(bitmapAllocations==bitmapFrees);
    }
    assert(!Bytes::Allocate(0,bitmapAllocate,bitmapFree)&&!Bytes::Allocate(1,bitmapFailAllocate,bitmapFree));
    for(unsigned n=0;n<200;++n){
        auto owner=Bytes::Allocate(64,bitmapAllocate,bitmapFree);std::vector<std::thread> threads;
        for(unsigned t=0;t<8;++t)threads.emplace_back([owner]{owner->markDataRelease();owner->release();});
        for(auto &thread:threads){thread.join();}
        assert(owner->dataReleased()&&!owner->data());owner.reset();assert(bitmapAllocations==bitmapFrees);
    }
    std::puts("Bitmap resources passed: 32x8x10k color memo races, failure/reentry recovery, 100k zeroed shared-byte leases, early data-release acknowledgements and 200x8 exact-once retire races.");
}
