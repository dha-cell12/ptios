#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cerrno>

namespace TLinkHistoryRecoveryCompare {
struct Read {
    std::ptrdiff_t count;
    int error;
    Read(std::ptrdiff_t value,int code=0):count(value),error(code){}
};
enum class Result {Exact,Different,ReadFailed,BufferFailed,Invalid};
// Read the same bounded byte sequence once. Allocate a full fallback only on
// the first mismatch; reconstruct its already verified prefix without rereads.
// Providers are synchronous. The allocated storage must remain owned by caller.
template<class Reader,class Allocate>
Result Compare(const uint8_t *expected,std::size_t length,Reader read,Allocate allocate){
    if(!expected&&length)return Result::Invalid;
    uint8_t chunk[65536];
    uint8_t *storage=nullptr;
    std::size_t offset=0;
    while(offset<length){
        const std::size_t remaining=length-offset;
        const std::size_t count=remaining<sizeof(chunk)?remaining:sizeof(chunk);
        uint8_t *destination=storage?storage+offset:chunk;
        const Read got=read(destination,count);
        if(got.count<0&&got.error==EINTR)continue;
        if(got.count<=0||static_cast<std::size_t>(got.count)>count)return Result::ReadFailed;
        const std::size_t bytes=static_cast<std::size_t>(got.count);
        if(!storage&&std::memcmp(chunk,expected+offset,bytes)!=0){
            storage=allocate(length);
            if(!storage)return Result::BufferFailed;
            if(offset)std::memcpy(storage,expected,offset);
            std::memcpy(storage+offset,chunk,bytes);
        }
        offset+=bytes;
    }
    return storage?Result::Different:Result::Exact;
}
}
