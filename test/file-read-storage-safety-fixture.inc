#include "../shared/TLinkJSFileReadStorage.h"
#include <map>
#include <cstdlib>
#include <cstring>
namespace FileReadStorageFixture {
struct Allocations {
    std::map<void *,size_t> live;
    size_t calls=0,fail=SIZE_MAX,raises=SIZE_MAX,maximum=0;
    static void *resize(void *context,void *old,size_t size){
        auto &trace=*static_cast<Allocations *>(context);++trace.calls;
        if(trace.calls==trace.raises)throw std::runtime_error("allocate");
        if(trace.calls==trace.fail)return nullptr;
        void *next=std::malloc(size);if(!next)return nullptr;
        std::memset(next,0xa5,size);
        if(old){const auto found=trace.live.find(old);assert(found!=trace.live.end());
            std::memcpy(next,old,std::min(size,found->second));trace.live.erase(found);std::free(old);}
        assert(trace.live.emplace(next,size).second);trace.maximum=std::max(trace.maximum,size);return next;
    }
    static void destroy(void *context,void *bytes){auto &trace=*static_cast<Allocations *>(context);assert(trace.live.erase(bytes)==1);std::free(bytes);}
    TLinkPersistenceJSONStorage::Allocator allocator(){return {this,resize,destroy};}
};
using Buffer=TLinkJSFileReadStorage::Buffer;
static Result execute(Source &source,size_t limit,bool line,bool regular,Allocations &trace){
    Buffer storage(limit,trace.allocator());Result result;
    const auto grow=[&](size_t used,size_t count){return storage.destination(used,count);};
    if(line){
        const auto input=TLinkJSFileReadLineInto(limit,regular,grow,[&](uint8_t *p,size_t n){return source.read(p,n);},[&](size_t n){return source.rewind(n);});
        result.error=input.error;result.eof=input.eof;
        if(result.error)return result;
        size_t produced=input.bytes;if(produced&&storage.data()[produced-1]=='\r')--produced;
        assert(storage.seal(produced));
    }else{
        const auto input=TLinkJSFileIO::ReadInto(limit,grow,[&](uint8_t *p,size_t n){return source.read(p,n);});
        result.error=input.error;result.eof=input.eof;
        if(result.error)return result;
        assert(storage.seal(input.bytes));
    }
    assert(storage.capacity()<=limit&&storage.size()<=storage.capacity());
    if(storage.size())result.bytes.assign(reinterpret_cast<const char *>(storage.data()),storage.size());
    result.truncated=!result.eof&&result.bytes.size()==limit;return result;
}
static Result before(Source &source,size_t limit,bool line,bool regular){
    if(line)return directLine(source,limit,regular);
    Result result;std::vector<uint8_t> bytes;
    const auto input=TLinkJSFileIO::ReadInto(limit,[&](size_t used,size_t count){bytes.resize(used+count);return bytes.data()+used;},[&](uint8_t *p,size_t n){return source.read(p,n);});
    result.error=input.error;result.eof=input.eof;
    if(!input.error){result.bytes.assign(bytes.begin(),bytes.begin()+input.bytes);result.truncated=!result.eof&&input.bytes==limit;}
    return result;
}
static void compare(Source source,size_t limit,bool line,bool regular){
    Allocations trace;Source old=source,now=source;
    const auto expected=before(old,limit,line,regular),actual=execute(now,limit,line,regular,trace);
    assert(expected.error==actual.error&&old.offset==now.offset&&old.reads==now.reads&&old.rewinds==now.rewinds);
    if(!actual.error)assert(expected.bytes==actual.bytes&&expected.eof==actual.eof&&expected.truncated==actual.truncated);
    assert(trace.live.empty()&&trace.maximum<=limit);
}
static void faults(){
    for(size_t failure:{size_t(1),size_t(2),size_t(3)}){
        Allocations trace;trace.fail=failure;Source source;source.bytes=std::string(40000,'x');
        const auto result=execute(source,524288,false,true,trace);
        assert(result.error==ENOMEM&&source.reads==failure-1&&source.offset==(failure-1)*8192&&trace.live.empty());
    }
    for(bool line:{false,true}){
        Allocations trace;trace.raises=2;Source source;source.bytes=std::string(20000,'x');bool caught=false;
        try{(void)execute(source,524288,line,true,trace);}catch(const std::runtime_error &){caught=true;}
        assert(caught&&trace.live.empty()&&source.offset==(line?129U:8192U));
    }
    Allocations trace;
    {
        Buffer storage(524288,trace.allocator());uint8_t *first=storage.destination(0,8192);
        assert(first&&first[0]==0xa5&&first[8191]==0xa5&&storage.size()==0);std::memset(first,'q',8192);
        const uintptr_t previousEnd=reinterpret_cast<uintptr_t>(first)+8192;
        uint8_t *second=storage.destination(8192,8192);assert(second&&reinterpret_cast<uintptr_t>(second)!=previousEnd&&second[0]==0xa5);
        assert(storage.seal(8193)&&storage.size()==8193&&storage.data()[8191]=='q');
        Buffer moved(std::move(storage));assert(moved.size()==8193&&moved.data()[8191]=='q');
        assert(!moved.destination(8193,1)&&!moved.seal(8193));
    }
    assert(trace.live.empty());
    for(unsigned invalid=0;invalid<4;++invalid){
        Buffer storage(16);assert(!storage.destination(invalid==0?1:0,invalid==1?17:(invalid==2?SIZE_MAX:0)));
        assert(!storage.seal(0));
    }
    {Buffer empty(0);assert(empty.seal(0)&&!empty.size()&&!empty.capacity());}
    {Buffer edge(SIZE_MAX);assert(edge.destination(0,1)&&!edge.destination(1,SIZE_MAX));}
    {Buffer cr(4);uint8_t *p=cr.destination(0,1);assert(p);*p='\r';p=cr.destination(1,3);assert(p);*p='\n';assert(cr.seal(0));}
    {Buffer invalid(16);assert(invalid.destination(0,1)&&!invalid.seal(2));}
}
static void cases(){
    uint32_t state=0x3159ca72;
    const auto next=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(unsigned n=0;n<100000;++n){
        Source source;source.bytes.resize(next()%1024);
        for(char &byte:source.bytes){const auto value=next();byte=value%19==0?'\n':(value%23==0?'\r':char(value%256));}
        source.maxRead=1+next()%129;source.interrupts=next()%4;
        if(n%3==0)source.fault=source.bytes.empty()?0:next()%source.bytes.size();
        source.rewindFails=n%7==0;compare(source,next()%2048,n%3!=0,n%5!=0);
    }
    for(size_t length:{size_t(0),size_t(1),size_t(127),size_t(128),size_t(129),size_t(255),size_t(8191),size_t(8192),size_t(8193),size_t(524287),size_t(524288),size_t(524289)}){
        Source source;source.bytes=std::string(length,'x')+"\r\nrest";
        for(bool line:{false,true}){compare(source,524288,line,true);compare(source,length+1,line,true);}
    }
    // A fixed full transfer asks for the same 64 destinations while raw
    // capacity grows only at the seven geometric boundaries (controlled counts).
    Allocations trace;Source full;full.bytes=std::string(524288,'x');
    const auto complete=execute(full,524288,false,true,trace);
    assert(!complete.error&&complete.bytes==full.bytes&&full.reads==64&&trace.calls==7&&trace.live.empty());
    faults();
    puts("File raw read storage passed: 100k frozen numeric/line content/position/EOF/syscall oracles, moving poisoned allocations, bounded geometric capacity, 512-KiB/CR boundaries, EINTR/short/IO/rewind faults, allocation refusal/unwind and sealed/moved ownership; zero live blocks.");
}
}
