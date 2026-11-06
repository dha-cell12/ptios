static void wireSizeCases(){
    using namespace TLinkAXWireOutput;
    assert(MaxSuccessWireBytes==1048576);
    const size_t maxJSON=((MaxSuccessWireBytes-5)/4)*3;
    for(uint64_t n=0;n<100000;++n){
        const size_t bytes=static_cast<size_t>((n*104729)%(maxJSON+7));
        const size_t expected=5+4*((bytes+2)/3);size_t wire=17;
        const bool allowed=SuccessSize(bytes,wire);
        assert(allowed==(expected<=MaxSuccessWireBytes));
        assert(wire==(allowed?expected:17));
    }
    size_t wire=17;
    assert(SuccessSize(maxJSON,wire)&&wire==1048573);
    wire=17;assert(!SuccessSize(maxJSON+1,wire)&&wire==17);
    for(size_t bytes:{std::numeric_limits<size_t>::max(),std::numeric_limits<size_t>::max()-1})
        assert(!SuccessSize(bytes,wire)&&wire==17);
    assert(SuccessSize(0,wire)&&wire==5);
    assert(SuccessSize(1,wire)&&wire==9);
    assert(SuccessSize(2,wire)&&wire==9);
    assert(SuccessSize(3,wire)&&wire==9);
    assert(SuccessSize(4,wire)&&wire==13);
    std::puts("AX success wire passed: 100k exact JSON/base64/prefix/CRLF plans, 786426/786427-byte JSON boundary, 1-MiB cap, size_t overflow and unchanged size on refusal.");
}
