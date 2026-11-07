#include "../shared/TLinkJSFileLineInto.h"
static Result directLine(Source &source,size_t limit,bool regular=true){
    Result result;std::vector<uint8_t> storage;uint8_t *destination=nullptr;size_t offered=0;
    const auto line=TLinkJSFileReadLineInto(limit,regular,
        [&](size_t used,size_t count)->uint8_t * {
            assert(used<=limit&&count<=limit-used&&count<=8192&&used<=storage.size());
            // Always move storage while the old allocation is still live.
            // Only the committed prefix survives a grow; pointers cannot persist.
            std::vector<uint8_t> next(used+count,0xcd);
            assert(storage.empty()||next.data()!=storage.data());
            std::copy(storage.begin(),storage.begin()+used,next.begin());storage.swap(next);
            destination=storage.data()+used;offered=count;return destination;
        },[&](uint8_t *bytes,size_t count)->int64_t {
            assert(bytes==destination&&count==offered);return source.read(bytes,count);
        },[&](size_t count){return source.rewind(count);});
    result.error=line.error;result.eof=line.eof;
    assert(line.bytes<=storage.size()&&storage.size()<=limit);
    if(result.error)return result;
    result.bytes.assign(storage.begin(),storage.begin()+line.bytes);
    if(!result.bytes.empty()&&result.bytes.back()=='\r')result.bytes.pop_back();
    result.truncated=!result.eof&&result.bytes.size()==limit;return result;
}
static void directLineCompare(Source source,size_t limit,bool regular=true){
    Source old=source,now=source;
    const auto expected=current(old,limit,regular),actual=directLine(now,limit,regular);
    assert(expected.error==actual.error&&old.offset==now.offset&&old.reads==now.reads&&old.rewinds==now.rewinds);
    if(!actual.error)assert(expected.bytes==actual.bytes&&expected.eof==actual.eof&&expected.truncated==actual.truncated);
}
static void fileLineFillFaultCases(){
    for(unsigned failure=1;failure<=3;++failure){
        Source source;source.bytes=std::string(20000,'x')+"\nrest";
        std::vector<uint8_t> storage;unsigned grows=0;
        const auto line=TLinkJSFileReadLineInto(30000,true,
            [&](size_t used,size_t count)->uint8_t * {
                if(++grows==failure)return nullptr;
                storage.resize(used+count);return storage.data()+used;
            },[&](uint8_t *p,size_t n){return source.read(p,n);},[&](size_t n){return source.rewind(n);});
        const size_t committed=failure==1?0:(failure==2?1:129);
        assert(line.error==ENOMEM&&line.bytes==committed&&source.offset==committed&&source.reads==failure-1);
    }
    unsigned reads=0,grows=0;
    const auto empty=TLinkJSFileReadLineInto(0,true,[&](size_t,size_t)->uint8_t *{++grows;return nullptr;},[&](uint8_t *,size_t)->int64_t{++reads;return 0;},[](size_t){assert(false);return false;});
    assert(!empty.error&&!empty.eof&&!empty.bytes&&!reads&&!grows);
    uint8_t bytes[8192]={};
    const auto over=TLinkJSFileReadLineInto(1,true,[&](size_t,size_t){return bytes;},[](uint8_t *,size_t n){return int64_t(n+1);},[](size_t){assert(false);return false;});
    assert(over.error==EIO&&!over.bytes);
    const auto missingErrno=TLinkJSFileReadLineInto(1,true,[&](size_t,size_t){return bytes;},[](uint8_t *,size_t)->int64_t{errno=0;return -1;},[](size_t){assert(false);return false;});
    assert(missingErrno.error==EIO&&!missingErrno.bytes);
    for(unsigned site=0;site<3;++site){
        Source source;source.bytes="abc\nrest";std::vector<uint8_t> storage;unsigned growsCount=0;bool caught=false;
        try {
            (void)TLinkJSFileReadLineInto(1024,true,
                [&](size_t used,size_t count)->uint8_t * {
                    if(++growsCount==2&&site==0)throw std::runtime_error("grow");
                    storage.resize(used+count);return storage.data()+used;
                },[&](uint8_t *p,size_t n){const auto got=source.read(p,n);if(source.reads==2&&site==1)throw std::runtime_error("read");return got;},
                [&](size_t n){const bool result=source.rewind(n);if(site==2)throw std::runtime_error("rewind");return result;});
        }catch(const std::runtime_error &){caught=true;}
        assert(caught&&source.offset==(site==0?1U:(site==1?8U:4U)));
    }
    Source maximum;maximum.bytes="abc\nrest";directLineCompare(maximum,SIZE_MAX);
}
static void fileLineFillCases(){
    for(size_t boundary:{size_t(0),size_t(1),size_t(127),size_t(128),size_t(129),size_t(8191),size_t(8192),size_t(8321),size_t(524288)}){
        Source source;source.bytes=std::string(boundary,'x')+"\r\nrest";
        for(size_t extra=0;extra<4;++extra)directLineCompare(source,boundary+extra);
        source.rewindFails=true;directLineCompare(source,boundary+10);
    }
    uint32_t state=0x719a39ce;
    const auto next=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(unsigned n=0;n<100000;++n){
        Source source;source.bytes.resize(next()%512);
        for(char &byte:source.bytes){const auto value=next();byte=value%17==0?'\n':(value%19==0?'\r':char(value%256));}
        source.maxRead=1+next()%128;source.interrupts=next()%4;
        if(n%3==0)source.fault=source.bytes.empty()?0:next()%source.bytes.size();
        source.rewindFails=n%7==0;
        directLineCompare(source,next()%1024,n%5!=0);
    }
    fileLineFillFaultCases();
    Source large;large.bytes=std::string(524288,'x');Source old=large;
    const auto a=current(old,1048576),b=directLine(large,1048576);
    assert(a.bytes==b.bytes&&old.reads==large.reads&&large.reads==67);
    std::puts("Direct line core passed: 100k frozen chunk/position/EOF/CR/error/count oracles, moving destinations, limit/SIZE_MAX, EINTR/short reads/rewind faults, null growth and grow/read/rewind unwind; same 67 reads for a 512-KiB line without the production staging append.");
}
