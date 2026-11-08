#pragma once
#import <Foundation/Foundation.h>

// Private read staging. Callers validate the byte limit before construction and
// commit only produced bytes. No NSData is published until all bytes commit.
@interface TLinkOwnedReadBuffer : NSObject
- (instancetype _Nullable)initWithLength:(NSUInteger)length;
@property(nonatomic,readonly) NSUInteger length;
@property(nonatomic,readonly) NSUInteger committedLength;
@property(nonatomic,readonly) void * _Nullable mutableBytes;
- (BOOL)commitBytes:(NSUInteger)length;
- (NSData * _Nullable)takeData;
@end
