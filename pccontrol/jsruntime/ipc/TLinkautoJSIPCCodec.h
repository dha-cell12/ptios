#ifndef TLINKAUTO_JS_IPC_CODEC_H
#define TLINKAUTO_JS_IPC_CODEC_H

#import <Foundation/Foundation.h>
#include "TLinkautoJSIPCProtocol.h"

@interface TLinkautoJSIPCCodec : NSObject

+ (NSData *)encodeMessageWithType:(uint16_t)type
                        requestId:(uint64_t)requestId
                            runId:(uint64_t)runId
                       generation:(uint64_t)generation
                          timeout:(uint32_t)timeoutMs
                          payload:(NSDictionary *)payload;

+ (BOOL)decodeHeader:(NSData *)headerData into:(TLinkautoJSIPCHeader *)headerOut;
+ (NSDictionary *)decodePayload:(NSData *)payloadData error:(NSError **)error;

@end

#endif /* TLINKAUTO_JS_IPC_CODEC_H */
