#pragma once
#import <Foundation/Foundation.h>
#include "TLinkEventWireEncoding.h"

// The legacy Task-95 contract is ASCII framing around base64 JSON bytes.
// Return nil on the existing nil/empty JSON result; callers keep their error policy.
static inline NSData *TLinkEventLegacyBatchResponse(NSDictionary *batch)
{
    @autoreleasepool {
    NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
    const size_t bytes=json.length;
    if (!bytes) return nil;
    size_t length=0;
    if (!TLinkEventWireEncoding::Size(bytes,length)) return nil;
    NSMutableData *response = [NSMutableData dataWithLength:length];
    if (!response || !TLinkEventWireEncoding::Encode((const uint8_t *)json.bytes,bytes,
                                                   (uint8_t *)response.mutableBytes,response.length)) return nil;
    return response;
    }
}
