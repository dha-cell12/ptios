#pragma once
#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>

struct TLinkJSFileLineIntoResult { std::size_t bytes=0; bool eof=false; int error=0; };
// Each grow supplies the current destination tail. No pointer survives the next
// grow, and callers publish only result.bytes after checking error. Match the
// existing chunk sizes and restore unread tail bytes before returning success.
template<class Grow,class Read,class Rewind>
TLinkJSFileLineIntoResult TLinkJSFileReadLineInto(std::size_t limit,bool regular,
                                                Grow grow,Read readChunk,Rewind rewindTail)
{
    TLinkJSFileLineIntoResult result;
    while(result.bytes<limit){
        const std::size_t quantum=!regular||result.bytes==0?1:(result.bytes<129?128:8192);
        const std::size_t amount=std::min(quantum,limit-result.bytes);
        uint8_t *destination=grow(result.bytes,amount);
        if(!destination){result.error=ENOMEM;return result;}
        const int64_t got=readChunk(destination,amount);
        if(got<0){if(errno==EINTR)continue;result.error=errno?errno:EIO;return result;}
        if(!got){result.eof=true;return result;}
        if(uint64_t(got)>amount){result.error=EIO;return result;}
        const std::size_t count=static_cast<std::size_t>(got);
        const uint8_t *lf=static_cast<const uint8_t *>(std::memchr(destination,'\n',count));
        const std::size_t bytes=lf?static_cast<std::size_t>(lf-destination):count;
        const std::size_t tail=lf?count-bytes-1:0;
        if(tail&&!rewindTail(tail)){result.error=errno?errno:EIO;return result;}
        result.bytes+=bytes;
        if(lf)return result;
    }
    return result;
}
