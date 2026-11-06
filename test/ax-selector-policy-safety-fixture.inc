static void selectorPolicyCases(){
    using namespace TLinkAXSelectorPolicy;
    for(size_t n=0;n<100000;++n){
        const size_t units=n*37%100000,bytes=n*89%300000;
        assert(AdmitUTF16(units)==(units<=65536));
        assert(AdmitUTF8(bytes)==(bytes<=65536));
    }
    assert(AdmitUTF16(0)&&AdmitUTF8(0)&&AdmitUTF16(65536)&&AdmitUTF8(65536));
    assert(!AdmitUTF16(65537)&&!AdmitUTF8(65537));
    assert(!AdmitUTF16(std::numeric_limits<size_t>::max())&&!AdmitUTF8(std::numeric_limits<size_t>::max()));
    std::puts("AX selector policy passed: 100k UTF16/UTF8 admission plans, exact 64-KiB, zero, one-over and size_t boundaries.");
}
