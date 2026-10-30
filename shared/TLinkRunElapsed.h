#ifndef TLINK_RUN_ELAPSED_H
#define TLINK_RUN_ELAPSED_H
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>

// Caller serializes access. Track only committed local starts, never persisted clocks.
template<size_t Capacity=50> class TLinkRunElapsed {
    static_assert(Capacity>0,"elapsed capacity must be positive");
    struct Entry {std::string scope,id;uint64_t wall=0,mono=0;};
    std::array<Entry,Capacity> entries_{};
    size_t size_=0;
    static bool bounded(const char *text,size_t limit){
        if(!text||!text[0])return false;
        for(size_t n=0;n<=limit;++n)if(!text[n])return true;
        return false;
    }
    size_t find(const char *scope,const char *id) const {
        for(size_t n=0;n<size_;++n)if(entries_[n].scope==scope&&entries_[n].id==id)return n;
        return size_;
    }
    void erase(size_t index){
        for(size_t n=index+1;n<size_;++n)entries_[n-1]=std::move(entries_[n]);
        entries_[--size_]=Entry{};
    }
public:
    size_t size() const {return size_;}
    static uint64_t wallDuration(uint64_t start,uint64_t end){return end>=start?end-start:0;}
    bool remember(const char *scope,const char *id,uint64_t wall,uint64_t mono){
        if(!bounded(scope,4096)||!bounded(id,96))return false;
        if(mono==UINT64_MAX){forget(scope,id);return false;}
        Entry next{std::string(scope),std::string(id),wall,mono}; // allocate before changing admission state
        const size_t existing=find(scope,id);if(existing<size_)erase(existing);
        if(size_==Capacity)erase(0);
        entries_[size_]=std::move(next);++size_;return true;
    }
    void forget(const char *scope,const char *id){
        if(!bounded(scope,4096)||!bounded(id,96))return;
        const size_t index=find(scope,id);if(index<size_)erase(index);
    }
    uint64_t duration(const char *scope,const char *id,uint64_t wallStart,uint64_t wallEnd,uint64_t monoNow) const {
        const uint64_t fallback=wallDuration(wallStart,wallEnd);
        if(!bounded(scope,4096)||!bounded(id,96)||monoNow==UINT64_MAX)return fallback;
        const size_t index=find(scope,id);
        if(index==size_||entries_[index].wall!=wallStart||monoNow<entries_[index].mono)return fallback;
        return monoNow-entries_[index].mono;
    }
};
#endif
