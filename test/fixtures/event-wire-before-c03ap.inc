#pragma once
#import <Foundation/Foundation.h>

// The legacy Task-95 contract is ASCII framing around base64 JSON bytes.
// Return nil on the existing nil/empty JSON result; callers keep their error policy.
static inline NSData *TLinkEventLegacyBatchResponse(NSDictionary *batch)
{
    NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
    if (!json.length) return nil;
    NSData *base64 = [json base64EncodedDataWithOptions:0];
    NSMutableData *response = [NSMutableData dataWithBytes:"0;;" length:3];
    [response appendData:base64];
    [response appendBytes:"\r\n" length:2];
    return response;
}
