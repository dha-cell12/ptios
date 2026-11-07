#pragma once
#include <cstddef>
#include <cstdint>
#include <limits>

namespace TLinkEventPreparation {
// The journal reader validates sequence ordering before publishing its snapshot.
template<class Sequence>
size_t FirstAfter(size_t count,uint64_t cursor,Sequence sequence){
    if(!count)return 0;
    if(sequence(count-1)<=cursor)return count;
    size_t first=0,last=count;
    while(first<last){
        const size_t middle=first+(last-first)/2;
        if(sequence(middle)<=cursor)first=middle+1;else last=middle;
    }
    return first;
}
inline size_t Reserve(size_t requested,size_t available,size_t maximum){
    const size_t cap=requested<maximum?requested:maximum;
    return cap<available?cap:available;
}
class ByteCount {
    size_t bytes_=0;bool failed_=false;
public:
    bool append(size_t length){
        if(failed_||length>std::numeric_limits<size_t>::max()-bytes_){failed_=true;return false;}
        bytes_+=length;return true;
    }
    size_t size() const{return bytes_;}
    bool failed() const{return failed_;}
};
}
