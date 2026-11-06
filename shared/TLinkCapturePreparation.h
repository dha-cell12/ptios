#pragma once
#import <Foundation/Foundation.h>
#include <mutex>
#include "TLinkCapturePlan.h"

namespace TLinkCapturePreparation {
using Key=TLinkCapturePlan::Key;
inline NSDictionary *MakeProperties(const Key &key){
    return @{@"IOSurfaceAllocSize":@(key.allocation),@"IOSurfaceBytesPerElement":@4,
        @"IOSurfaceBytesPerRow":@(key.row),
        @"IOSurfaceWidth":key.signedDimensions?@((int)key.width):@(key.width),
        @"IOSurfaceHeight":key.signedDimensions?@((int)key.height):@(key.height),
        @"IOSurfacePixelFormat":@1111970369,@"IOSurfaceIsGlobal":key.global?@YES:@NO};
}
class Properties {
    struct Entry {Key key;__strong NSDictionary *value=nil;};
    Entry entries_[4];size_t next_=0;
    std::mutex mutex_;
public:
    NSDictionary *get(const Key &key){
        if(!TLinkCapturePlan::Valid(key))return nil;
        {std::lock_guard<std::mutex> lock(mutex_);for(const auto &entry:entries_)if(entry.value&&entry.key==key)return entry.value;}
        NSDictionary *candidate=nil;
        @autoreleasepool{candidate=MakeProperties(key);}
        if(!candidate)return nil;
        std::lock_guard<std::mutex> lock(mutex_);
        for(const auto &entry:entries_)if(entry.value&&entry.key==key)return entry.value;
        entries_[next_].key=key;entries_[next_].value=candidate;next_=(next_+1)%4;
        return candidate;
    }
};
template<class GetDevice>
bool RotateIPad(TLinkCapturePlan::BoolMemo &memo,GetDevice getDevice){
    bool value=false;if(memo.read(value))return value;
    @autoreleasepool{
        NSString *device=getDevice();
        if(!device.length)return false; // A failed/empty probe must retry.
        NSRange range=[device rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch];
        return memo.publish(range.location!=NSNotFound);
    }
}
}
