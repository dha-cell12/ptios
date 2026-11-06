static void outputBudgetCases(){
    using namespace TLinkAXSnapshotOutput;
    const size_t maximum=std::numeric_limits<size_t>::max();
    assert(MaxStringUTF8Bytes==65536);
    for(size_t n=0;n<100000;++n){
        const size_t bytes=n%65537,rowStart=768+n%1000,current=n*97;
        size_t row=rowStart,next=0,wire=0;
        assert(AddString(bytes,row)&&row==rowStart+6*bytes);
        assert(AppendRow(row,current,next,wire));
        assert(next==current+row&&wire==32768+4*((current+row+2)/3));
    }
    size_t row=768,next=17,wire=19;
    assert(!AddString(65537,row)&&row==768);
    assert(!AddString(maximum,row)&&row==768);
    row=maximum-5;assert(!AddString(1,row)&&row==maximum-5);
    row=maximum-6;assert(AddString(1,row)&&row==maximum);
    assert(!AppendRow(1,maximum,next,wire)&&next==17&&wire==19);
    assert(!AppendRow(maximum,0,next,wire)&&next==17&&wire==19);
    // Exact wire boundary and the first unrepresentable base64 group.
    const size_t groups=(maximum-32768)/4;
    assert(AppendRow(groups*3,0,next,wire)&&wire==32768+4*groups);
    next=17;wire=19;
    assert(!AppendRow(groups*3+1,0,next,wire)&&next==17&&wire==19);
    assert(AppendRow(0,0,next,wire)&&next==0&&wire==32768);
    std::puts("AX snapshot output passed: 100k frozen JSON/base64 estimates, 64-KiB string boundary, checked row/aggregate/wire overflow and unchanged outputs on refusal.");
}
