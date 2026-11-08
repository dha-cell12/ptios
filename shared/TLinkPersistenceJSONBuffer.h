#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <utility>

namespace TLinkPersistenceJSONStorage {
inline void *Resize(void *,void *bytes,std::size_t size){return std::realloc(bytes,size);}
inline void Destroy(void *,void *bytes){std::free(bytes);}
struct Allocator {
    // Realloc failure/throw must retain the old allocation; destroy cannot throw.
    // A supplied context must outlive the stream and every published NSData.
    void *context;
    void *(*resize)(void *,void *,std::size_t);
    void (*destroy)(void *,void *);
    Allocator():context(nullptr),resize(Resize),destroy(Destroy){}
    Allocator(void *c,void *(*r)(void *,void *,std::size_t),void (*d)(void *,void *))
        :context(c),resize(r),destroy(d){}
};
enum class Error {None,Limit,Allocation,Invalid,Sealed};
class Buffer {
    uint8_t *bytes_=nullptr;
    std::size_t size_=0,capacity_=0,limit_=0;
    bool sealed_=false;
    Error error_=Error::None;
    Allocator allocator_;
public:
    explicit Buffer(std::size_t limit=0,Allocator allocator=Allocator()):limit_(limit),allocator_(allocator){}
    Buffer(const Buffer &)=delete;
    Buffer &operator=(const Buffer &)=delete;
    Buffer(Buffer &&other) noexcept { *this=std::move(other); }
    Buffer &operator=(Buffer &&other) noexcept {
        if(this!=&other){
            release();bytes_=other.bytes_;size_=other.size_;capacity_=other.capacity_;limit_=other.limit_;
            sealed_=other.sealed_;error_=other.error_;allocator_=other.allocator_;
            other.bytes_=nullptr;other.size_=other.capacity_=other.limit_=0;other.sealed_=true;
        }
        return *this;
    }
    ~Buffer(){release();}
    // Source chunks must not overlap this growable allocation.
    bool append(const uint8_t *bytes,std::size_t count){
        if(error_!=Error::None)return false;
        if(sealed_){error_=Error::Sealed;return false;}
        if(count>limit_-size_){error_=Error::Limit;return false;}
        if((!bytes&&count)||!allocator_.resize||!allocator_.destroy){error_=Error::Invalid;return false;}
        const std::size_t required=size_+count;
        if(required>capacity_){
            std::size_t capacity=capacity_?capacity_:(limit_<256?limit_:256);
            while(capacity<required)capacity=capacity>limit_/2?limit_:capacity*2;
            void *next=allocator_.resize(allocator_.context,bytes_,capacity);
            if(!next){error_=Error::Allocation;return false;}
            bytes_=static_cast<uint8_t *>(next);capacity_=capacity;
        }
        if(count)std::memcpy(bytes_+size_,bytes,count);
        size_=required;return true;
    }
    // Reserve storage without initializing it; no bytes become visible in size().
    bool reserveForRead(std::size_t count){
        if(error_!=Error::None)return false;
        if(sealed_||size_){error_=Error::Invalid;return false;}
        if(count>limit_){error_=Error::Limit;return false;}
        if(!allocator_.resize||!allocator_.destroy){error_=Error::Invalid;return false;}
        if(count>capacity_){
            void *next=allocator_.resize(allocator_.context,bytes_,count);
            if(!next){error_=Error::Allocation;return false;}
            bytes_=static_cast<uint8_t *>(next);capacity_=count;
        }
        return true;
    }
    uint8_t *writableData(){return !sealed_&&error_==Error::None?bytes_:nullptr;}
    bool commitRead(std::size_t count){
        if(error_!=Error::None)return false;
        if(sealed_){error_=Error::Sealed;return false;}
        if(count>capacity_-size_){error_=Error::Limit;return false;}
        size_+=count;return true;
    }
    bool seal(){if(sealed_||error_!=Error::None)return false;sealed_=true;return true;}
    void release() noexcept {
        if(bytes_)allocator_.destroy(allocator_.context,bytes_);
        bytes_=nullptr;size_=capacity_=0;sealed_=true;
    }
    const uint8_t *data()const{return bytes_;}
    std::size_t size()const{return size_;}
    std::size_t capacity()const{return capacity_;}
    Error error()const{return error_;}
};
}
