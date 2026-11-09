#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <utility>
// An exact-content memo for a previously validated scalar, not a file cache.
// Callers must perform their checked fresh read before every lookup.
class TLinkEventStatusCache {
public:
    using Bytes=std::unique_ptr<uint8_t[]>;
    using Allocate=Bytes (*)(std::size_t);
    static Bytes NewBytes(std::size_t size){return Bytes(new uint8_t[size]);}
    static const std::size_t Limit=2*1024*1024;
private:
    std::mutex mutex_;
    std::size_t limit_,size_=0;
    uint64_t value_=0;
    Allocate allocate_;
    Bytes bytes_;
    void reset(){bytes_.reset();size_=0;value_=0;}
public:
    explicit TLinkEventStatusCache(std::size_t limit=Limit,Allocate allocate=NewBytes):limit_(limit),allocate_(allocate){}
    bool lookup(const uint8_t *bytes,std::size_t size,uint64_t &value) noexcept {
        if(!bytes||!size||size>limit_)return false;
        try {std::lock_guard<std::mutex> lock(mutex_);
            if(size!=size_||!bytes_||std::memcmp(bytes,bytes_.get(),size)!=0)return false;
            value=value_;return true;
        }catch(...) {return false;}
    }
    bool store(const uint8_t *bytes,std::size_t size,uint64_t value) noexcept {
        try {std::lock_guard<std::mutex> lock(mutex_);reset();
            if(!bytes||!size||size>limit_||!allocate_)return false;
            Bytes next=allocate_(size);if(!next)return false;
            std::memcpy(next.get(),bytes,size);bytes_=std::move(next);size_=size;value_=value;return true;
        }catch(...) {return false;}
    }
    void clear() noexcept {try {std::lock_guard<std::mutex> lock(mutex_);reset();}catch(...) {}}
    std::size_t retainedBytes() noexcept {try {std::lock_guard<std::mutex> lock(mutex_);return size_;}catch(...) {return 0;}}
};
