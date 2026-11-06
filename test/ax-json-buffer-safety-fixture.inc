struct JSONAllocationTrace {
    size_t live=0,bytes=0,requests=0,releases=0,maximum=0,failAt=0;
    bool throwResize=false;
};
static void *tracedJSONResize(void *context,void *previous,size_t count){
    auto &trace=*static_cast<JSONAllocationTrace *>(context);++trace.requests;
    assert(count>0&&count<=TLinkAXJSONOutput::MaxJSONBytes);
    trace.maximum=std::max(trace.maximum,count);
    if(trace.throwResize)throw std::runtime_error("resize");
    if(trace.failAt&&trace.requests==trace.failAt)return nullptr;
    void *next=std::realloc(previous,count);assert(next);
    if(!previous)++trace.live;
    trace.bytes=count;return next;
}
static void tracedJSONFree(void *context,void *bytes){
    auto &trace=*static_cast<JSONAllocationTrace *>(context);assert(bytes&&trace.live==1);
    --trace.live;trace.bytes=0;++trace.releases;std::free(bytes);
}
static void jsonBufferCases(){
    using namespace TLinkAXJSONOutput;
    const uint8_t chunk[]={1,2,3,4,5,6,7,8};
    for(unsigned n=0;n<20000;++n){
        JSONAllocationTrace trace;
        {
            Buffer buffer(Allocator(&trace,tracedJSONResize,tracedJSONFree));
            assert(buffer.append(nullptr,0)&&trace.requests==0);
            for(unsigned i=0;i<n%33+1;++i)assert(buffer.append(chunk,sizeof(chunk)));
            assert(buffer.size()==(n%33+1)*sizeof(chunk)&&buffer.capacity()<=MaxJSONBytes);
            for(size_t i=0;i<buffer.size();++i)assert(buffer.data()[i]==chunk[i%sizeof(chunk)]);
            const uint8_t *pointer=buffer.data();assert(buffer.seal());
            Buffer owned(std::move(buffer));assert(owned.data()==pointer&&buffer.data()==nullptr);
            assert(!buffer.append(chunk,1)&&!owned.append(chunk,1));
            assert(owned.data()==pointer&&owned.size()==(n%33+1)*sizeof(chunk));
            owned.release();owned.release();assert(trace.live==0);
        }
        assert(trace.live==0&&trace.bytes==0&&trace.releases==1);
    }
    JSONAllocationTrace trace;
    {
        Buffer buffer(Allocator(&trace,tracedJSONResize,tracedJSONFree));
        std::vector<uint8_t> large(MaxJSONBytes,0x7b);
        assert(buffer.append(large.data(),large.size())&&buffer.capacity()==MaxJSONBytes);
        assert(!buffer.append(chunk,1)&&buffer.error()==BufferError::Limit&&buffer.size()==MaxJSONBytes);
    }
    assert(trace.live==0&&trace.maximum==MaxJSONBytes);
    for(unsigned failure:{1U,2U}){
        JSONAllocationTrace fault;fault.failAt=failure;
        {
            Buffer buffer(Allocator(&fault,tracedJSONResize,tracedJSONFree));
            if(failure==2)assert(buffer.append(chunk,sizeof(chunk)));
            const uint8_t *before=buffer.data();const size_t size=buffer.size();
            std::vector<uint8_t> large(1024,0x41);
            assert(!buffer.append(large.data(),large.size())&&buffer.error()==BufferError::Allocation);
            assert(buffer.data()==before&&buffer.size()==size&&!buffer.append(chunk,1));
        }
        assert(fault.live==0&&fault.bytes==0);
    }
    {
        JSONAllocationTrace fault;
        try{
            Buffer buffer(Allocator(&fault,tracedJSONResize,tracedJSONFree));assert(buffer.append(chunk,sizeof(chunk)));
            fault.throwResize=true;std::vector<uint8_t> large(1024,0);buffer.append(large.data(),large.size());assert(false);
        }catch(const std::runtime_error &){}
        assert(fault.live==0&&fault.releases==1);
    }
    Buffer invalid;assert(!invalid.append(nullptr,1)&&invalid.error()==BufferError::Invalid);
    Buffer overflow;assert(!overflow.append(chunk,std::numeric_limits<size_t>::max())&&overflow.error()==BufferError::Limit);
    std::puts("AX JSON storage passed: 20k exact-byte/move/seal/retire lifecycles, bounded requested capacity, max/overflow, initial/growing allocation faults and C++ resize unwind; zero live traced buffers.");
}
