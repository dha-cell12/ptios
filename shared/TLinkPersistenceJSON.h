#pragma once
#import <Foundation/Foundation.h>

// Complete JSON only. Refuse before accepting a chunk past the caller's limit;
// no filesystem effects occur here. Writer exceptions retain their propagation.
FOUNDATION_EXPORT NSData *TLinkPersistenceJSONData(id object,NSJSONWritingOptions options,NSUInteger limit);
