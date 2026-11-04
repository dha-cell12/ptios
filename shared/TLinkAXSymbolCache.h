#ifndef TLINK_AX_SYMBOL_CACHE_H
#define TLINK_AX_SYMBOL_CACHE_H
#include <atomic>

namespace TLinkAXSymbols {
struct Snapshot {void *handle;void *first;void *second;};

// A fixed symbol borrowed from one caller-pinned library. Never opens/closes
// the handle. Successful pointers stay published; missing lookups retry.
class Symbol {
    const char *name_;
    std::atomic<void *> value_{nullptr};
public:
    explicit Symbol(const char *name):name_(name){}
    Symbol(const Symbol &)=delete;
    Symbol &operator=(const Symbol &)=delete;
    template<class Lookup>
    void *load(void *handle,Lookup lookup){
        if(!handle)return nullptr;
        void *value=value_.load(std::memory_order_acquire);
        if(!value){
            void *found=lookup(handle,name_);
            if(found){
                void *empty=nullptr;
                value_.compare_exchange_strong(empty,found,std::memory_order_acq_rel,std::memory_order_acquire);
            }
            value=value_.load(std::memory_order_acquire);
        }
        return value;
    }
};

// Fixed library/symbol names per instance. One successful dlopen reference is
// pinned for process lifetime; concurrent extra references are balanced. No
// cache lock is held across loader calls (which can re-enter application code).
class Cache {
    const char *path_,*firstName_,*secondName_;
    std::atomic<void *> handle_{nullptr},first_{nullptr},second_{nullptr};
    template<class Lookup>
    static void *resolve(std::atomic<void *> &slot,void *handle,const char *name,Lookup &lookup){
        void *value=slot.load(std::memory_order_acquire);
        if(!value){
            void *found=lookup(handle,name);
            if(found){
                void *empty=nullptr;
                slot.compare_exchange_strong(empty,found,std::memory_order_acq_rel,std::memory_order_acquire);
            }
            value=slot.load(std::memory_order_acquire);
        }
        return value;
    }
public:
    Cache(const char *path,const char *first,const char *second):path_(path),firstName_(first),secondName_(second){}
    Cache(const Cache &)=delete;
    Cache &operator=(const Cache &)=delete;
    template<class Open,class Lookup,class Close>
    Snapshot load(Open open,Lookup lookup,Close close,bool includeSecond=true){
        void *handle=handle_.load(std::memory_order_acquire);
        if(!handle){
            void *candidate=open(path_);
            if(candidate){
                void *empty=nullptr;
                if(!handle_.compare_exchange_strong(empty,candidate,std::memory_order_acq_rel,std::memory_order_acquire))close(candidate);
            }
            handle=handle_.load(std::memory_order_acquire);
        }
        if(!handle)return {nullptr,nullptr,nullptr};
        return {handle,resolve(first_,handle,firstName_,lookup),includeSecond?resolve(second_,handle,secondName_,lookup):nullptr};
    }
    // Resolve only when the caller actually reaches its fallback. Never opens
    // another handle; before successful load(), there is nothing to resolve.
    template<class Lookup>
    void *loadSecond(Lookup lookup){
        void *handle=handle_.load(std::memory_order_acquire);
        return handle?resolve(second_,handle,secondName_,lookup):nullptr;
    }
};
}
#endif
