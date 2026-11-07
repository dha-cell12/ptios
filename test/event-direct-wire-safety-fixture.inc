#include "../shared/TLinkEventWireEncoding.h"
#include <algorithm>
// Independent bit-accumulator oracle, including explicit final padding.
static std::string eventWireOracle(const std::vector<uint8_t> &bytes){
    const std::string table="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string result="0;;";uint32_t accumulator=0;unsigned bits=0;
    for(uint8_t byte:bytes){
        accumulator=(accumulator<<8)|byte;bits+=8;
        while(bits>=6){bits-=6;result.push_back(table[(accumulator>>bits)&63]);}
    }
    if(bits)result.push_back(table[(accumulator<<(6-bits))&63]);
    while((result.size()-3)%4)result.push_back('=');
    return result+"\r\n";
}
static void eventDirectWireCheck(const std::vector<uint8_t> &bytes){
    const std::string expected=eventWireOracle(bytes);size_t length=0;
    assert(TLinkEventWireEncoding::Size(bytes.size(),length)&&length==expected.size());
    std::vector<uint8_t> output(length+2,0xa7);
    assert(TLinkEventWireEncoding::Encode(bytes.data(),bytes.size(),output.data()+1,length));
    assert(std::equal(expected.begin(),expected.end(),output.begin()+1)&&output.front()==0xa7&&output.back()==0xa7);
    std::fill(output.begin(),output.end(),uint8_t(0xa7));
    assert(!TLinkEventWireEncoding::Encode(bytes.data(),bytes.size(),output.data()+1,length-1));
    assert(std::all_of(output.begin(),output.end(),[](uint8_t byte){return byte==0xa7;}));
}
static void eventDirectWireCases(){
    const char *inputs[]={"","f","fo","foo","foob","fooba","foobar"};
    const char *encoded[]={"","Zg==","Zm8=","Zm9v","Zm9vYg==","Zm9vYmE=","Zm9vYmFy"};
    for(size_t n=0;n<7;++n){
        const std::string text=inputs[n];std::vector<uint8_t> bytes(text.begin(),text.end());
        assert(eventWireOracle(bytes)==std::string("0;;")+encoded[n]+"\r\n");eventDirectWireCheck(bytes);
    }
    for(unsigned value=0;value<256;++value){
        eventDirectWireCheck({uint8_t(value)});
        for(unsigned other=0;other<256;++other)eventDirectWireCheck({uint8_t(value),uint8_t(other)});
    }
    uint32_t state=0xab7163e9;
    const auto next=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(unsigned n=0;n<100000;++n){
        std::vector<uint8_t> bytes(next()%1024);
        for(uint8_t &byte:bytes){byte=uint8_t(next());}
        eventDirectWireCheck(bytes);
    }
    for(size_t count:{size_t(4095),size_t(4096),size_t(4097),size_t(131072),size_t(1048576),size_t(1048577)}){
        std::vector<uint8_t> bytes(count);
        for(uint8_t &byte:bytes){byte=uint8_t(next());}
        eventDirectWireCheck(bytes);
    }
    const size_t maximum=std::numeric_limits<size_t>::max();
    size_t first=0,last=maximum;
    while(first<last){const size_t middle=first+(last-first)/2+1;size_t result=17;
        if(TLinkEventWireEncoding::Size(middle,result))first=middle;else last=middle-1;}
    const size_t expectedMaximum=3*((maximum-5)/4);
    size_t result=0;assert(first==expectedMaximum&&TLinkEventWireEncoding::Size(first,result)&&result==5+4*((maximum-5)/4));
    for(size_t n=1;n<=8;++n){result=17;assert(!TLinkEventWireEncoding::Size(first+n,result)&&result==17);}
    uint8_t bytes[16];std::fill(bytes,bytes+16,uint8_t(0x5a));
    assert(!TLinkEventWireEncoding::Encode(nullptr,1,bytes,sizeof(bytes)));
    assert(!TLinkEventWireEncoding::Encode(bytes,1,nullptr,16));
    assert(!TLinkEventWireEncoding::Encode(bytes,maximum,bytes,sizeof(bytes)));
    assert(std::all_of(bytes,bytes+16,[](uint8_t byte){return byte==0x5a;}));
    assert(TLinkEventWireEncoding::Encode(nullptr,0,bytes,5)&&std::string((char *)bytes,5)=="0;;\r\n");
    std::puts("Direct event wire core passed: 100k independent bit-stream oracles, all 256 single/65536 double-byte cases, exact padding/RFC vectors, output canaries/refusal without prefix, SIZE_MAX size boundary and 4-KiB/128-KiB/over-1-MiB payloads.");
}
