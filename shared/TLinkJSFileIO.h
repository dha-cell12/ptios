#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cerrno>

namespace TLinkJSFileIO {
struct Result {std::size_t bytes=0;int error=0;bool eof=false,zeroWrite=false;};
// Grow returns writable storage at the logical end; no pointer survives another grow.
// Trim to result.bytes before exposing successful data. Errors publish no prefix.
template<class Grow,class Read>
Result ReadInto(std::size_t limit,Grow grow,Read readChunk){
    Result result;
    while(result.bytes<limit){
        const std::size_t amount=std::min(std::size_t(8192),limit-result.bytes);
        uint8_t *destination=grow(result.bytes,amount);
        if(!destination){result.error=ENOMEM;return result;}
        const int64_t got=readChunk(destination,amount);
        if(got<0){if(errno==EINTR)continue;result.error=errno?errno:EIO;return result;}
        if(!got){result.eof=true;return result;}
        if(uint64_t(got)>amount){result.error=EIO;return result;}
        result.bytes+=static_cast<std::size_t>(got);
    }
    return result;
}
template<class Write>
Result WriteAll(const uint8_t *bytes,std::size_t length,Write writeChunk){
    Result result;
    if(length&&!bytes){result.error=EFAULT;return result;}
    while(result.bytes<length){
        const std::size_t remaining=length-result.bytes;
        const int64_t wrote=writeChunk(bytes+result.bytes,remaining);
        if(wrote<0){if(errno==EINTR)continue;result.error=errno?errno:EIO;return result;}
        if(!wrote){result.zeroWrite=true;return result;}
        if(uint64_t(wrote)>remaining){result.error=EIO;return result;}
        result.bytes+=static_cast<std::size_t>(wrote);
    }
    return result;
}
}
