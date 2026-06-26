#import "TLinkJSHelperProtocol.h"

NSString * const kTLinkJSHelperProtocolVersion = @"1.0";

NSString * const kTLinkJSHelperKeyProtocolVersion = @"protocolVersion";
NSString * const kTLinkJSHelperKeyCommand = @"command";
NSString * const kTLinkJSHelperKeyHelperInstanceId = @"helperInstanceId";
NSString * const kTLinkJSHelperKeySessionId = @"sessionId";
NSString * const kTLinkJSHelperKeyRequestId = @"requestId";
NSString * const kTLinkJSHelperKeyStateSequence = @"stateSequence";
NSString * const kTLinkJSHelperKeyPayload = @"payload";
NSString * const kTLinkJSHelperKeyError = @"error";

NSString * const kTLinkJSHelperCmdHandshake = @"handshake";
NSString * const kTLinkJSHelperCmdStart = @"start";
NSString * const kTLinkJSHelperCmdStop = @"stop";
NSString * const kTLinkJSHelperCmdStatus = @"status";
NSString * const kTLinkJSHelperCmdStateChanged = @"stateChanged";
NSString * const kTLinkJSHelperCmdFetchLogs = @"fetchLogs";
NSString * const kTLinkJSHelperCmdNativeRPCRequest = @"nativeRPCRequest";
NSString * const kTLinkJSHelperCmdNativeRPCResponse = @"nativeRPCResponse";
NSString * const kTLinkJSHelperCmdError = @"error";

NSString * const kTLinkJSHelperStateIdle = @"idle";
NSString * const kTLinkJSHelperStateStarting = @"starting";
NSString * const kTLinkJSHelperStateRunning = @"running";
NSString * const kTLinkJSHelperStateStopping = @"stopping";
NSString * const kTLinkJSHelperStateCompleted = @"completed";
NSString * const kTLinkJSHelperStateCancelled = @"cancelled";
NSString * const kTLinkJSHelperStateFailed = @"failed";
NSString * const kTLinkJSHelperStateCrashed = @"crashed";

@implementation TLinkJSHelperProtocol

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"TLinkJSHelperProtocol" code:-1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"invalid protocol envelope"}];
}

+ (NSSet *)allowedCommands {
    static NSSet *commands = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commands = [NSSet setWithObjects:kTLinkJSHelperCmdHandshake,
                    kTLinkJSHelperCmdStart,
                    kTLinkJSHelperCmdStop,
                    kTLinkJSHelperCmdStatus,
                    kTLinkJSHelperCmdStateChanged,
                    kTLinkJSHelperCmdFetchLogs,
                    kTLinkJSHelperCmdNativeRPCRequest,
                    kTLinkJSHelperCmdNativeRPCResponse,
                    kTLinkJSHelperCmdError, nil];
    });
    return commands;
}

+ (NSSet *)allowedStates {
    static NSSet *states = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        states = [NSSet setWithObjects:kTLinkJSHelperStateIdle,
                  kTLinkJSHelperStateStarting,
                  kTLinkJSHelperStateRunning,
                  kTLinkJSHelperStateStopping,
                  kTLinkJSHelperStateCompleted,
                  kTLinkJSHelperStateCancelled,
                  kTLinkJSHelperStateFailed,
                  kTLinkJSHelperStateCrashed, nil];
    });
    return states;
}

+ (NSDictionary *)envelopeWithCommand:(NSString *)command
                     helperInstanceId:(NSString *)helperInstanceId
                            sessionId:(NSString *)sessionId
                            requestId:(NSString *)requestId
                              payload:(NSDictionary *)payload {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[kTLinkJSHelperKeyProtocolVersion] = kTLinkJSHelperProtocolVersion;
    if (command) env[kTLinkJSHelperKeyCommand] = command;
    if (helperInstanceId) env[kTLinkJSHelperKeyHelperInstanceId] = helperInstanceId;
    if (sessionId) env[kTLinkJSHelperKeySessionId] = sessionId;
    if (requestId) env[kTLinkJSHelperKeyRequestId] = requestId;
    if (payload) env[kTLinkJSHelperKeyPayload] = payload;
    return [env copy];
}

+ (BOOL)validateJSONObject:(id)obj error:(NSError **)error {
    if (!obj || obj == [NSNull null] || [obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) return YES;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if (![self validateJSONObject:item error:error]) return NO;
        }
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in [(NSDictionary *)obj allKeys]) {
            if (![key isKindOfClass:[NSString class]]) {
                if (error) *error = [self errorWithMessage:@"JSON dictionary keys must be strings"];
                return NO;
            }
            if (![self validateJSONObject:((NSDictionary *)obj)[key] error:error]) return NO;
        }
        return YES;
    }
    if (error) *error = [self errorWithMessage:@"payload contains non-JSON value"];
    return NO;
}

+ (BOOL)validateEnvelope:(NSDictionary *)envelope error:(NSError **)error {
    if (![envelope isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [self errorWithMessage:@"Envelope is not a dictionary"];
        return NO;
    }
    if (![envelope[kTLinkJSHelperKeyProtocolVersion] isKindOfClass:[NSString class]] || ![envelope[kTLinkJSHelperKeyProtocolVersion] isEqualToString:kTLinkJSHelperProtocolVersion]) {
        if (error) *error = [self errorWithMessage:@"Missing, invalid, or incompatible protocolVersion"];
        return NO;
    }
    NSString *command = envelope[kTLinkJSHelperKeyCommand];
    if (![command isKindOfClass:[NSString class]] || ![[self allowedCommands] containsObject:command]) {
        if (error) *error = [self errorWithMessage:@"Missing or invalid command"];
        return NO;
    }
    id payload = envelope[kTLinkJSHelperKeyPayload];
    if (payload && ![self validateJSONObject:payload error:error]) return NO;
    id helperInstanceId = envelope[kTLinkJSHelperKeyHelperInstanceId];
    if (helperInstanceId && ![helperInstanceId isKindOfClass:[NSString class]]) {
        if (error) *error = [self errorWithMessage:@"helperInstanceId must be a string"];
        return NO;
    }
    id sessionId = envelope[kTLinkJSHelperKeySessionId];
    if (sessionId && ![sessionId isKindOfClass:[NSString class]] && ![sessionId isKindOfClass:[NSNumber class]]) {
        if (error) *error = [self errorWithMessage:@"sessionId must be a string or number"];
        return NO;
    }
    id requestId = envelope[kTLinkJSHelperKeyRequestId];
    if (requestId && ![requestId isKindOfClass:[NSString class]] && ![requestId isKindOfClass:[NSNumber class]]) {
        if (error) *error = [self errorWithMessage:@"requestId must be a string or number"];
        return NO;
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStateChanged]) {
        NSDictionary *payloadDict = [payload isKindOfClass:[NSDictionary class]] ? (NSDictionary *)payload : nil;
        id stateSequence = envelope[kTLinkJSHelperKeyStateSequence] ?: payloadDict[kTLinkJSHelperKeyStateSequence];
        id state = payloadDict[@"state"];
        if (![stateSequence isKindOfClass:[NSNumber class]] || ![state isKindOfClass:[NSString class]] || ![[self allowedStates] containsObject:state]) {
            if (error) *error = [self errorWithMessage:@"stateChanged requires numeric stateSequence and valid state"];
            return NO;
        }
    }
    if ([command isEqualToString:kTLinkJSHelperCmdNativeRPCRequest]) {
        NSDictionary *payloadDict = [payload isKindOfClass:[NSDictionary class]] ? (NSDictionary *)payload : nil;
        id method = payloadDict[@"method"];
        id nativeRequestId = payloadDict[kTLinkJSHelperKeyRequestId];
        if (![method isKindOfClass:[NSString class]] || !nativeRequestId) {
            if (error) *error = [self errorWithMessage:@"nativeRPCRequest requires method and requestId"];
            return NO;
        }
    }
    if ([command isEqualToString:kTLinkJSHelperCmdNativeRPCResponse]) {
        NSDictionary *payloadDict = [payload isKindOfClass:[NSDictionary class]] ? (NSDictionary *)payload : nil;
        id nativeRequestId = payloadDict[kTLinkJSHelperKeyRequestId];
        id result = payloadDict[@"result"];
        if (!nativeRequestId || !result) {
            if (error) *error = [self errorWithMessage:@"nativeRPCResponse requires requestId and result"];
            return NO;
        }
    }
    return YES;
}

+ (NSData *)serializeEnvelope:(NSDictionary *)envelope error:(NSError **)error {
    if (![self validateEnvelope:envelope error:error]) {
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:envelope options:0 error:error];
}

+ (NSDictionary *)deserializeEnvelope:(NSData *)data error:(NSError **)error {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    for (NSUInteger i = 0; i < data.length; i++) {
        if (bytes[i] == '\n') {
            length = i;
            break;
        }
    }
    if (length != data.length) {
        data = [NSData dataWithBytes:bytes length:length];
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!obj) return nil;
    if ([self validateEnvelope:obj error:error]) {
        return obj;
    }
    return nil;
}

@end
