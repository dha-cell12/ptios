#ifndef TLINK_JS_FILE_LINE_H
#define TLINK_JS_FILE_LINE_H
#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>

struct TLinkJSFileLineResult { bool eof=false; int error=0; };
// No unread bytes survive the call. The private descriptor is restored to just
// after LF before publishing a chunk, so subsequent read/seek/write sees the
// original logical position and fresh file contents.
template<class Read,class Rewind,class Append>
TLinkJSFileLineResult TLinkJSFileReadLine(size_t limit,bool regular,Read readChunk,Rewind rewindTail,Append appendBytes)
{
    TLinkJSFileLineResult result;size_t used=0;uint8_t buffer[8192];
    while(used<limit){
        const size_t quantum=!regular||used==0?1:(used<129?128:sizeof(buffer));
        const size_t amount=std::min(quantum,limit-used);
        const int64_t got=readChunk(buffer,amount);
        if(got<0){if(errno==EINTR)continue;result.error=errno?errno:EIO;return result;}
        if(!got){result.eof=true;return result;}
        if(uint64_t(got)>amount){result.error=EIO;return result;}
        const size_t count=size_t(got);
        const uint8_t *lf=static_cast<const uint8_t *>(std::memchr(buffer,'\n',count));
        const size_t bytes=lf?size_t(lf-buffer):count;
        const size_t tail=lf?count-bytes-1:0;
        if(tail&&!rewindTail(tail)){result.error=errno?errno:EIO;return result;}
        if(bytes)appendBytes(buffer,bytes);
        used+=bytes;
        if(lf)return result;
    }
    return result;
}
#endif
