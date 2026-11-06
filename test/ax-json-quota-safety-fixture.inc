static void jsonQuotaCases(){
    using namespace TLinkAXJSONOutput;
    assert(MaxJSONBytes==786426);
    for(uint64_t n=0;n<100000;++n){
        Quota quota;size_t accepted=0;bool failed=false;
        for(unsigned step=0;step<4;++step){
            const size_t count=static_cast<size_t>((n*104729+step*65537)%(MaxJSONBytes*2+7));
            const bool expected=!failed&&count<=MaxJSONBytes-accepted;
            assert(quota.append(count)==expected);
            if(expected)accepted+=count;else failed=true;
            assert(quota.size()==accepted&&quota.exceeded()==failed);
        }
    }
    Quota exact;assert(exact.append(MaxJSONBytes-1)&&exact.append(1)&&exact.append(0));
    assert(!exact.append(1)&&exact.exceeded()&&exact.size()==MaxJSONBytes&&!exact.append(0));
    Quota overflow;assert(!overflow.append(std::numeric_limits<size_t>::max())&&overflow.size()==0&&overflow.exceeded());
    Quota other;assert(other.append(1)&&other.size()==1&&!other.exceeded());
    std::puts("AX JSON quota passed: 100k chunk/oracle lifecycles, exact 786426/786427 boundary, terminal rejection, size_t overflow and independent counters.");
}
