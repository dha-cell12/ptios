#import "TLinkautoJSIPCCodec.h"

@implementation TLinkautoJSIPCCodec

+ (NSData *)encodeMessageWithType:(uint16_t)type
                        requestId:(uint64_t)requestId
                            runId:(uint64_t)runId
                       generation:(uint64_t)generation
                          timeout:(uint32_t)timeoutMs
                          payload:(NSDictionary *)payload {

    NSData *payloadData = nil;
    if (payload) {
        NSError *error = nil;
        payloadData = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:0
                                                                  error:&error];
        if (error || !payloadData) {
            NSLog(@"com.tlinkauto.springboard: Failed to serialize IPC payload: %@", error);
            return nil;
        }
    }

    uint32_t payloadLen = payloadData ? (uint32_t)payloadData.length : 0;

    if (payloadLen > 1024 * 1024) { // Limit to 1MiB as per plan
        NSLog(@"com.tlinkauto.springboard: IPC payload too large (%u bytes)", payloadLen);
        return nil;
    }

    TLinkautoJSIPCHeader header;
    header.magic = TLJS_MAGIC;
    header.version = TLJS_VERSION;
    header.messageType = type;
    header.flags = 0;
    header.requestId = requestId;
    header.runId = runId;
    header.generation = generation;
    header.payloadLength = payloadLen;
    header.timeoutMs = timeoutMs;

    NSMutableData *packet = [NSMutableData dataWithCapacity:sizeof(TLinkautoJSIPCHeader) + payloadLen];
    [packet appendBytes:&header length:sizeof(TLinkautoJSIPCHeader)];
    if (payloadData) {
        [packet appendData:payloadData];
    }

    return packet;
}

+ (BOOL)decodeHeader:(NSData *)headerData into:(TLinkautoJSIPCHeader *)headerOut {
    if (headerData.length < sizeof(TLinkautoJSIPCHeader)) return NO;
    [headerData getBytes:headerOut length:sizeof(TLinkautoJSIPCHeader)];

    if (headerOut->magic != TLJS_MAGIC || headerOut->version != TLJS_VERSION) {
        return NO;
    }

    if (headerOut->payloadLength > 1024 * 1024) {
        return NO; // Safety limit 1MiB
    }

    return YES;
}

+ (NSDictionary *)decodePayload:(NSData *)payloadData error:(NSError **)error {
    if (!payloadData || payloadData.length == 0) return @{};

    id plist = [NSPropertyListSerialization propertyListWithData:payloadData
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:error];
    if ([plist isKindOfClass:[NSDictionary class]]) {
        return plist;
    }
    if (error) {
        *error = [NSError errorWithDomain:@"TLinkautoJSIPCCodec" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Payload is not a dictionary"}];
    }
    return nil;
}

@end
