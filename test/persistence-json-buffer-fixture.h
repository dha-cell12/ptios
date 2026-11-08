#pragma once
#include "../shared/TLinkPersistenceJSONBuffer.h"
#include <cassert>
#include <unordered_map>
#include <stdexcept>

namespace PersistenceStorageFixture {
struct Trace {
    std::unordered_map<void *,std::size_t> blocks;
    std::size_t requests=0,allocations=0,frees=0,maximum=0,failRequest=0;
    bool throwNext=false;
    static void *resize(void *context,void *bytes,std::size_t size){
        Trace &trace=*static_cast<Trace *>(context);++trace.requests;
        if(size>trace.maximum)trace.maximum=size;
        if(trace.throwNext){trace.throwNext=false;throw std::runtime_error("resize");}
        if(trace.requests==trace.failRequest)return nullptr;
        void *next=std::malloc(size);if(!next)return nullptr;
        ++trace.allocations;std::memset(next,0xa5,size);
        if(bytes){
            const auto old=trace.blocks.find(bytes);assert(old!=trace.blocks.end());
            std::memcpy(next,bytes,old->second<size?old->second:size);
            std::free(bytes);++trace.frees;trace.blocks.erase(old);
        }
        assert(trace.blocks.emplace(next,size).second);return next;
    }
    static void destroy(void *context,void *bytes){
        Trace &trace=*static_cast<Trace *>(context);assert(trace.blocks.erase(bytes)==1);
        ++trace.frees;std::free(bytes);
    }
    TLinkPersistenceJSONStorage::Allocator allocator(){return TLinkPersistenceJSONStorage::Allocator(this,resize,destroy);}
};
}
