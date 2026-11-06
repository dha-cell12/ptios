static void processPolicyCases(){
    using namespace TLinkAXProcessPolicy;
    for(size_t n=0;n<100000;++n){
        const size_t row=1+n%2048,reported=n*379%MaxTableBytes;
        size_t capacity=42;const bool fits=reported&&reported<=MaxTableBytes-row*SlackEntries;
        assert(Capacity(reported,row,capacity)==fits);
        if(fits){
            assert(capacity==reported+row*SlackEntries&&capacity<=MaxTableBytes);
            size_t count=42;assert(Count(reported,capacity,row,count)&&count==reported/row);
        }else assert(capacity==42);
    }
    size_t out=77;
    assert(!Capacity(0,1,out)&&!Capacity(1,0,out)&&!Capacity(1,std::numeric_limits<size_t>::max(),out));
    assert(!Capacity(std::numeric_limits<size_t>::max(),1,out)&&out==77);
    assert(Capacity(MaxTableBytes-SlackEntries,1,out)&&out==MaxTableBytes);
    out=77;assert(!Count(5,4,1,out)&&!Count(1,1,0,out)&&!Count(0,MaxTableBytes+1,1,out)&&out==77);
    assert(Count(7,8,3,out)&&out==2);
    char shortPath[]={'a','b','c',0};
    assert(Path(shortPath,sizeof(shortPath),3)&&!Path(shortPath,sizeof(shortPath),2));
    assert(!Path(shortPath,sizeof(shortPath),4)&&!Path(nullptr,4,3)&&!Path(shortPath,4,-1));
    char missing[]={'a','b','c','d'};assert(!Path(missing,sizeof(missing),3));
    std::vector<char> path(4096,'x');path.back()=0;
    assert(Path(path.data(),path.size(),4095));path[1]=0;assert(!Path(path.data(),path.size(),4095));
    std::puts("AX process policy passed: 100k bounded table/slack/count plans, size_t overflow, unchanged rejected outputs, partial rows and exact/NUL/missing/oversize path boundaries.");
}
