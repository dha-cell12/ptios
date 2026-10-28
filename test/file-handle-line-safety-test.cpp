#include "../shared/TLinkJSFileLine.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
struct Source {
    std::string bytes;size_t offset=0,reads=0,rewinds=0,maxRead=8192,fault=SIZE_MAX;unsigned interrupts=0;bool rewindFails=false;
    int64_t read(uint8_t *out,size_t size){
        ++reads;if(interrupts){--interrupts;errno=EINTR;return -1;}
        if(offset>=fault){errno=EIO;return -1;}
        const size_t count=std::min(std::min(size,maxRead),std::min(bytes.size()-offset,fault-offset));
        if(count)std::memcpy(out,bytes.data()+offset,count);offset+=count;return int64_t(count);
    }
    bool rewind(size_t count){++rewinds;if(rewindFails){errno=EIO;return false;}assert(count<=offset);offset-=count;return true;}
};
struct Result {std::string bytes;bool eof=false,truncated=false;int error=0;};
static Result legacy(Source &source,size_t limit){
    Result result;
    while(result.bytes.size()<limit){
        uint8_t byte=0;const int64_t got=source.read(&byte,1);
        if(!got){result.eof=true;break;}
        if(got<0){if(errno==EINTR)continue;result.error=errno;return result;}
        if(byte=='\n')break;result.bytes+=char(byte);
    }
    if(!result.bytes.empty()&&result.bytes.back()=='\r')result.bytes.pop_back();
    result.truncated=!result.eof&&result.bytes.size()==limit;return result;
}
static Result current(Source &source,size_t limit,bool regular=true){
    Result result;const auto line=TLinkJSFileReadLine(limit,regular,
        [&source](uint8_t *bytes,size_t count){return source.read(bytes,count);},
        [&source](size_t count){return source.rewind(count);},
        [&result](const uint8_t *bytes,size_t count){result.bytes.append(reinterpret_cast<const char *>(bytes),count);});
    result.eof=line.eof;result.error=line.error;
    if(result.error)return result;
    if(!result.bytes.empty()&&result.bytes.back()=='\r')result.bytes.pop_back();
    result.truncated=!result.eof&&result.bytes.size()==limit;return result;
}
static void compare(Source source,size_t limit,bool regular=true){
    Source old=source,now=source;const auto want=legacy(old,limit),got=current(now,limit,regular);
    assert(got.error==want.error&&now.offset==old.offset);
    if(!got.error)assert(got.bytes==want.bytes&&got.eof==want.eof&&got.truncated==want.truncated);
    if(!regular)assert(now.reads==old.reads&&now.rewinds==0);
}
int main(){
    for(const std::string &bytes:std::vector<std::string>{"","\n","\r\n","a\nnext","a\r","a\r\nnext","\r","\r\n\n",std::string("a\0b\nnext",8),std::string(20000,'x')+"\nrest"}){
        for(size_t limit:{size_t(1),size_t(2),size_t(3),size_t(128),size_t(129),size_t(8192),size_t(32768)}){
            Source source;source.bytes=bytes;compare(source,limit);compare(source,limit,false);
            for(size_t part:{size_t(1),size_t(7),size_t(127)}){source.maxRead=part;source.interrupts=3;compare(source,limit);}
        }
    }
    uint32_t random=0x12345678;
    const auto next=[&random](){random^=random<<13;random^=random>>17;random^=random<<5;return random;};
    for(unsigned n=0;n<10000;++n){
        Source source;const size_t count=next()%2048;source.bytes.resize(count);
        for(char &byte:source.bytes){const auto value=next();byte=value%19==0?'\n':(value%23==0?'\r':char(value%256));}
        source.maxRead=1+next()%8192;source.interrupts=next()%4;const size_t limit=1+next()%1024;
        compare(source,limit);source.fault=count?next()%count:0;compare(source,limit);
        // Multiple lines preserve physical position without a persistent cache.
        source.fault=SIZE_MAX;Source old=source,now=source;
        while(now.offset<now.bytes.size()){
            const auto want=legacy(old,limit),got=current(now,limit);assert(got.bytes==want.bytes&&got.eof==want.eof&&got.truncated==want.truncated&&now.offset==old.offset);
        }
    }
    Source large;large.bytes=std::string(512*1024,'x');Source old=large;
    const auto want=legacy(old,1024*1024),got=current(large,1024*1024);
    assert(got.bytes==want.bytes&&got.eof&&large.offset==old.offset&&large.reads<70&&old.reads==512*1024+1);
    Source failed;failed.bytes="abcdef\nremaining";failed.rewindFails=true;
    const auto error=current(failed,1024);assert(error.error==EIO&&failed.rewinds==1);
    Source unwind;unwind.bytes="abc\nrest";
    unsigned appends=0;
    try{TLinkJSFileReadLine(1024,true,[&unwind](uint8_t *p,size_t n){return unwind.read(p,n);},[&unwind](size_t n){return unwind.rewind(n);},[&appends](const uint8_t *,size_t){if(++appends==2)throw std::runtime_error("append");});assert(false);}catch(const std::runtime_error &){}
    assert(unwind.offset==4&&unwind.rewinds==1); // tail restored before append unwind
    for(size_t boundary:{size_t(1),size_t(127),size_t(128),size_t(129),size_t(8191),size_t(8192),size_t(8321)}){
        Source edge;edge.bytes=std::string(boundary,'x')+"\r\nrest";compare(edge,boundary);compare(edge,boundary+1);compare(edge,boundary+2);compare(edge,boundary+3);
    }
    unsigned reads=0;
    const auto invalid=TLinkJSFileReadLine(1,true,[&reads](uint8_t *,size_t n){++reads;return int64_t(n+1);},[](size_t){assert(false);return false;},[](const uint8_t *,size_t){assert(false);});
    assert(invalid.error==EIO&&reads==1);
    const auto zero=TLinkJSFileReadLine(0,true,[](uint8_t *,size_t)->int64_t{assert(false);return 0;},[](size_t){assert(false);return false;},[](const uint8_t *,size_t){assert(false);});
    assert(!zero.error&&!zero.eof);
    std::printf("File line core passed: 10k frozen byte/position/EOF/CR/limit/fault cases, short reads/EINTR, nonregular fallback, tail rewind/unwind; 512-KiB line reads %zu versus %zu legacy syscalls.\n",large.reads,old.reads);
}
