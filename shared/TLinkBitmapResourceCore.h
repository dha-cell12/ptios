#pragma once
#include <atomic>
#include <memory>
#include <cstdlib>
#include <cstddef>
#include <new>

namespace TLinkBitmapCore {
template<class Ref>
class Memo {
    std::atomic<Ref> value_{Ref()};
    void (*drop_)(Ref);
public:
    explicit Memo(void (*drop)(Ref)):drop_(drop){}
    ~Memo(){Ref value=value_.load();if(value)drop_(value);}
    Memo(const Memo &)=delete;Memo &operator=(const Memo &)=delete;
    template<class Make> Ref get(Make make){
        Ref value=value_.load(std::memory_order_acquire);
        if(value)return value;
        Ref candidate=make();if(!candidate)return value_.load(std::memory_order_acquire);
        Ref empty=Ref();
        if(!value_.compare_exchange_strong(empty,candidate,std::memory_order_acq_rel,std::memory_order_acquire))drop_(candidate);
        return value_.load(std::memory_order_acquire);
    }
};
class Bytes {
    std::atomic<void *> data_;
    size_t size_;
    void (*drop_)(void *);
    std::atomic<bool> dataReleased_{false};
public:
    Bytes(void *data,size_t size,void (*drop)(void *)):data_(data),size_(size),drop_(drop){}
    ~Bytes(){release();}
    Bytes(const Bytes &)=delete;Bytes &operator=(const Bytes &)=delete;
    void *data()const{return data_.load(std::memory_order_acquire);}
    size_t size()const{return size_;}
    void markDataRelease(){dataReleased_.store(true,std::memory_order_release);}
    bool dataReleased()const{return dataReleased_.load(std::memory_order_acquire);}
    void release(){void *data=data_.exchange(nullptr,std::memory_order_acq_rel);if(data)drop_(data);}
    static std::shared_ptr<Bytes> Allocate(size_t size,void *(*allocate)(size_t,size_t)=&std::calloc,void (*drop)(void *)=&std::free){
        if(!size)return {};
        void *data=allocate(1,size);if(!data)return {};
        try{return std::make_shared<Bytes>(data,size,drop);}
        catch(const std::bad_alloc &){drop(data);return {};}
    }
};
}
