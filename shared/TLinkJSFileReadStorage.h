#pragma once
#include "TLinkPersistenceJSONBuffer.h"

namespace TLinkJSFileReadStorage {
// ReadInto/ReadLineInto supply the produced prefix. A destination may include
// unread slack; only the successful core's final byte count can be sealed.
// The line caller may remove its last CR before sealing; no raw bytes escape
// through the script API. This is an operation-local owner, not thread safe.
class Buffer {
    TLinkPersistenceJSONStorage::Buffer storage_;
    std::size_t limit_,lastUsed_=0,offeredEnd_=0;
    bool failed_=false,finished_=false;
public:
    explicit Buffer(std::size_t limit,TLinkPersistenceJSONStorage::Allocator allocator=TLinkPersistenceJSONStorage::Allocator())
        :storage_(limit,allocator),limit_(limit){}
    Buffer(const Buffer &)=delete;
    Buffer &operator=(const Buffer &)=delete;
    Buffer(Buffer &&)=default;
    Buffer &operator=(Buffer &&)=default;
    uint8_t *destination(std::size_t used,std::size_t count){
        if(failed_||finished_)return nullptr;
        if(!count||used<lastUsed_||used>offeredEnd_||used>limit_||count>limit_-used){failed_=true;return nullptr;}
        const std::size_t required=used+count;
        if(required>storage_.capacity()){
            std::size_t capacity=storage_.capacity()?storage_.capacity():(limit_<256?limit_:256);
            while(capacity<required)capacity=capacity>limit_/2?limit_:capacity*2;
            if(!storage_.reserveForRead(capacity)){failed_=true;return nullptr;}
        }
        lastUsed_=used;offeredEnd_=required;
        return storage_.writableData()+used;
    }
    bool seal(std::size_t produced){
        if(failed_||finished_||produced>offeredEnd_)return false;
        if(!storage_.commitRead(produced)||!storage_.seal()){failed_=true;return false;}
        finished_=true;return true;
    }
    const uint8_t *data()const{return storage_.data();}
    std::size_t size()const{return storage_.size();}
    std::size_t capacity()const{return storage_.capacity();}
};
}
