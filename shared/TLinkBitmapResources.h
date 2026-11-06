#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "TLinkBitmapResourceCore.h"
#include "TLinkCaptureOwnership.h"

namespace TLinkBitmapResources {
// Borrow one successful process-local immutable RGB space. Consumers/CG
// contexts retain their own references as usual; failed creation retries.
inline CGColorSpaceRef DeviceRGB(){
    static TLinkBitmapCore::Memo<CGColorSpaceRef> memo(&CGColorSpaceRelease);
    return memo.get([]{return CGColorSpaceCreateDeviceRGB();});
}
inline NSData *CreateData(const std::shared_ptr<TLinkBitmapCore::Bytes> &owner){
    auto storage=owner;
    if(!storage||!storage->data()||!storage->size())return nil;
    // The producer and Foundation's deallocator both hold the same owner.
    // A copying/early-callback implementation must not retire producer bytes.
    // The final shared owner frees once, including nil/throwing factory paths.
    return [[NSData alloc] initWithBytesNoCopy:storage->data() length:storage->size()
        deallocator:^(void *bytes,NSUInteger size){(void)bytes;(void)size;storage->markDataRelease();}];
}
inline NSData *Data(const std::shared_ptr<TLinkBitmapCore::Bytes> &owner){return CreateData(owner);}
}
