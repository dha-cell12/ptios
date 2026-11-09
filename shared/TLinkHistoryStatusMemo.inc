#pragma once
#include "TLinkHistoryProjectionBudget.h"
#include <memory>
#include <mutex>
#include <algorithm>
namespace TLinkHistoryStatusMemo {
static const NSUInteger ByteLimit=2*1024*1024;
// JSON-derived leaves are copied without serialization or number normalization.
static id CopyGraph(id value,bool mutableContainers,TLinkHistoryProjectionBudget &budget,size_t depth=0){
    if(!budget.node(depth))return nil;
    if([value isKindOfClass:[NSString class]])return budget.text([value length])?[value copy]:nil;
    if([value isKindOfClass:[NSNumber class]])return [value copy];
    if(value==[NSNull null])return value;
    if([value isKindOfClass:[NSArray class]]){
        const NSUInteger count=[value count];
        NSMutableArray *copy=[NSMutableArray arrayWithCapacity:std::min((size_t)count,budget.remaining())];if(!copy)return nil;
        for(id child in value){@autoreleasepool {
            id item=CopyGraph(child,mutableContainers,budget,depth+1);if(!item)return nil;[copy addObject:item];
        }}
        if(mutableContainers)return copy;
        return [copy copy];
    }
    if([value isKindOfClass:[NSDictionary class]]){
        const NSUInteger count=[value count];
        NSMutableDictionary *copy=[NSMutableDictionary dictionaryWithCapacity:std::min((size_t)count,budget.remaining())];if(!copy)return nil;
        for(id key in value){@autoreleasepool {
            if(![key isKindOfClass:[NSString class]])return nil;
            id ownedKey=CopyGraph(key,false,budget,depth+1);if(!ownedKey)return nil;
            id child=CopyGraph(value[key],mutableContainers,budget,depth+1);if(!child)return nil;
            copy[ownedKey]=child;
        }}
        if(mutableContainers)return copy;
        return [copy copy];
    }
    return nil;
}
struct Entry {
    NSData *bytes;
    NSArray *rows;
    NSUInteger limit,total,failed;
    Entry(NSData *data,NSArray *projection,NSUInteger selected,NSUInteger count,NSUInteger failures)
        :bytes(data),rows(projection),limit(selected),total(count),failed(failures){}
};
static std::mutex &Mutex(){static std::mutex mutex;return mutex;}
static std::shared_ptr<const Entry> &Stored(){static std::shared_ptr<const Entry> value;return value;}
static std::shared_ptr<const Entry> Snapshot(){std::lock_guard<std::mutex> lock(Mutex());return Stored();}
static void Publish(std::shared_ptr<const Entry> value){
    std::shared_ptr<const Entry> retired;
    {std::lock_guard<std::mutex> lock(Mutex());retired.swap(Stored());Stored()=std::move(value);}
    // ARC payload retirement happens after releasing the private memo mutex.
}
static void Clear() noexcept {
    @try {try {Publish({});}catch(...) {}} @catch(NSException *exception){(void)exception;}
}
struct Read {
    NSUInteger limit,total=0,failed=0;
    NSData *bytes=nil;
    NSMutableArray *rows=nil;
    bool hit=false;
    explicit Read(NSUInteger value):limit(value){}
};
static bool Lookup(NSData *data,Read &read) noexcept {
    @autoreleasepool {@try {try {
        read.hit=false;read.rows=nil;read.total=read.failed=0;
        if(!data.length||data.length>ByteLimit){Clear();return false;}
        auto value=Snapshot();if(!value||value->limit!=read.limit||![value->bytes isEqualToData:data])return false;
        TLinkHistoryProjectionBudget budget;
        id rows=CopyGraph(value->rows,true,budget);if(!rows){Clear();return false;}
        if(![rows isKindOfClass:[NSMutableArray class]]){Clear();return false;}
        read.rows=rows;read.total=value->total;read.failed=value->failed;read.hit=true;return true;
    }catch(...) {Clear();}} @catch(NSException *exception){(void)exception;Clear();}}
    return false;
}
static void Offer(NSData *data,NSUInteger limit,NSArray *rows,NSUInteger total,NSUInteger failed) noexcept {
    @autoreleasepool {@try {try {
        if(!data.length||data.length>ByteLimit){Clear();return;}
        TLinkHistoryProjectionBudget budget;
        id projection=CopyGraph(rows,false,budget);if(![projection isKindOfClass:[NSArray class]]){Clear();return;}
        NSData *bytes=[data copy];if(!bytes||bytes.length!=data.length){Clear();return;}
        Publish(std::make_shared<Entry>(bytes,projection,limit,total,failed));
    }catch(...) {Clear();}} @catch(NSException *exception){(void)exception;Clear();}}
}
}
