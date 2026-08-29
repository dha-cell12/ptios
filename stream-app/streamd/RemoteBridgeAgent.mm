#import "RemoteBridgeAgent.h"
#import "POCSocketServer.h"
#import "../../shared/TLinkLicenseVerifier.h"
#import <UIKit/UIKit.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSString *const kTLinkRemoteConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkRemoteDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/remote_bridge.plist";
static const NSUInteger kTLinkRemoteMaxFrameBytes = 4 * 1024 * 1024;

static NSURL *TLinkRemoteURL(NSString *base, NSString *path, NSDictionary<NSString *, NSString *> *query)
{
    NSURLComponents *components = [NSURLComponents componentsWithString:base ?: @""];
    if (!components || ![components.scheme.lowercaseString isEqualToString:@"wss"] || components.host.length == 0) return nil;
    NSString *basePath = components.path ?: @"";
    if ([basePath isEqualToString:@"/"]) basePath = @"";
    components.path = [basePath stringByAppendingString:path];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        (void)stop;
        [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];
    components.queryItems = items.count > 0 ? items : nil;
    return components.URL;
}

static NSMutableURLRequest *TLinkRemoteRequest(NSURL *url, NSString *token)
{
    if (!url || token.length == 0) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20.0;
    [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    return request;
}

static BOOL TLinkReadExactly(int fd, void *buffer, size_t length)
{
    uint8_t *cursor = (uint8_t *)buffer;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t count = recv(fd, cursor, remaining, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        cursor += count;
        remaining -= (size_t)count;
    }
    return YES;
}

@interface TLinkRemoteVideoPump : NSObject <NSURLSessionWebSocketDelegate>
- (instancetype)initWithBaseURL:(NSString *)baseURL
                           token:(NSString *)token
                        deviceId:(NSString *)deviceId
                        streamId:(NSString *)streamId
                         profile:(NSString *)profile;
- (void)start;
- (void)stop;
@end

@implementation TLinkRemoteVideoPump {
    NSString *_baseURL;
    NSString *_token;
    NSString *_deviceId;
    NSString *_streamId;
    NSString *_profile;
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_task;
    dispatch_semaphore_t _sendSlots;
    int _socketFd;
    BOOL _stopped;
}

- (instancetype)initWithBaseURL:(NSString *)baseURL
                           token:(NSString *)token
                        deviceId:(NSString *)deviceId
                        streamId:(NSString *)streamId
                         profile:(NSString *)profile
{
    self = [super init];
    if (self) {
        _baseURL = [baseURL copy];
        _token = [token copy];
        _deviceId = [deviceId copy];
        _streamId = [streamId copy];
        _profile = [[profile ?: @"wan" lowercaseString] copy];
        _sendSlots = dispatch_semaphore_create(2);
        _socketFd = -1;
    }
    return self;
}

- (BOOL)isStopped
{
    @synchronized (self) { return _stopped; }
}

- (void)start
{
    NSURL *url = TLinkRemoteURL(_baseURL, @"/remote/device/video", @{
        @"device_id": _deviceId ?: @"",
        @"stream_id": _streamId ?: @"",
    });
    NSMutableURLRequest *request = TLinkRemoteRequest(url, _token);
    if (!request) return;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.waitsForConnectivity = YES;
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    _task = [_session webSocketTaskWithRequest:request];
    [_task resume];
}

- (void)stop
{
    @synchronized (self) {
        if (_stopped) return;
        _stopped = YES;
        if (_socketFd >= 0) {
            shutdown(_socketFd, SHUT_RDWR);
            close(_socketFd);
            _socketFd = -1;
        }
    }
    [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    [_session invalidateAndCancel];
}

- (void)URLSession:(NSURLSession *)session
     webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didOpenWithProtocol:(NSString *)protocol
{
    (void)session;
    (void)webSocketTask;
    (void)protocol;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self pumpFrames];
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    (void)session;
    (void)task;
    (void)error;
    [self stop];
}

- (void)pumpFrames
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { [self stop]; return; }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    uint16_t streamPort = [_profile isEqualToString:@"lan"] ? 7003 : 7006;
    address.sin_port = htons(streamPort);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        [self stop];
        return;
    }
    @synchronized (self) {
        if (_stopped) { close(fd); return; }
        _socketFd = fd;
    }

    while (![self isStopped]) {
        uint8_t header[52] = {0};
        if (!TLinkReadExactly(fd, header, sizeof(header))) break;
        if (memcmp(header, "ZXH2", 4) != 0) break;
        uint32_t payloadNetwork = 0;
        memcpy(&payloadNetwork, header + 48, sizeof(payloadNetwork));
        NSUInteger payloadLength = (NSUInteger)ntohl(payloadNetwork);
        if (payloadLength == 0 || payloadLength > kTLinkRemoteMaxFrameBytes) break;

        NSMutableData *packet = [NSMutableData dataWithLength:sizeof(header) + payloadLength];
        memcpy(packet.mutableBytes, header, sizeof(header));
        if (!TLinkReadExactly(fd, (uint8_t *)packet.mutableBytes + sizeof(header), payloadLength)) break;
        if (dispatch_semaphore_wait(_sendSlots,
                                    dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) break;
        NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:packet];
        [_task sendMessage:message completionHandler:^(NSError *error) {
            dispatch_semaphore_signal(self->_sendSlots);
            if (error) [self stop];
        }];
    }
    [self stop];
}

@end

@interface TLinkRemoteBridgeAgent : NSObject <NSURLSessionWebSocketDelegate>
- (void)start;
@end

@implementation TLinkRemoteBridgeAgent {
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_controlTask;
    NSMutableDictionary<NSString *, TLinkRemoteVideoPump *> *_videoPumps;
    NSString *_baseURL;
    NSString *_token;
    NSString *_deviceId;
    NSString *_state;
    NSString *_lastError;
    uint64_t _reconnectCount;
    BOOL _opened;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.tlinkauto.remote-bridge", DISPATCH_QUEUE_SERIAL);
        _videoPumps = [NSMutableDictionary dictionary];
        _state = @"disabled";
        _lastError = @"";
    }
    return self;
}

- (void)start
{
    dispatch_async(_queue, ^{
        if (self->_timer) return;
        self->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
        dispatch_source_set_timer(self->_timer,
                                  dispatch_time(DISPATCH_TIME_NOW, 0),
                                  5 * NSEC_PER_SEC,
                                  NSEC_PER_SEC);
        dispatch_source_set_event_handler(self->_timer, ^{ [self reconcile]; });
        dispatch_resume(self->_timer);
    });
}

- (NSDictionary *)configuration
{
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:kTLinkRemoteConfigPath];
    NSDictionary *remote = [root[@"remote_bridge"] isKindOfClass:[NSDictionary class]] ? root[@"remote_bridge"] : @{};
    return @{
        @"enabled": @([remote[@"enabled"] boolValue]),
        @"url": [remote[@"url"] isKindOfClass:[NSString class]] ? remote[@"url"] : @"",
        @"token": [remote[@"token"] isKindOfClass:[NSString class]] ? remote[@"token"] : @"",
    };
}

- (NSString *)resolvedDeviceId
{
    NSDictionary *license = TLinkLicenseStatusDictionary();
    NSString *deviceId = [license[@"device_id"] isKindOfClass:[NSString class]] ? license[@"device_id"] : @"";
    if (deviceId.length == 0) deviceId = [UIDevice currentDevice].identifierForVendor.UUIDString;
    if (deviceId.length == 0) deviceId = [NSString stringWithFormat:@"ios-%@", [NSUUID UUID].UUIDString];
    return deviceId;
}

- (void)writeDiagnostics
{
    NSString *parent = [kTLinkRemoteDiagnosticsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parent
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSDictionary *diagnostics = @{
        @"state": _state ?: @"unknown",
        @"url": _baseURL ?: @"",
        @"device_id": _deviceId ?: @"",
        @"last_error": _lastError ?: @"",
        @"reconnect_count": @(_reconnectCount),
        @"connected": @(_opened),
        @"active_video_streams": @(_videoPumps.count),
        @"updated_at_ms": @((uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0)),
    };
    [diagnostics writeToFile:kTLinkRemoteDiagnosticsPath atomically:YES];
}

- (void)reconcile
{
    NSDictionary *configuration = [self configuration];
    BOOL enabled = [configuration[@"enabled"] boolValue];
    NSString *url = configuration[@"url"];
    NSString *token = configuration[@"token"];
    NSString *licenseError = nil;
    BOOL licensed = TLinkLicenseFeatureAllowed(@"automation", &licenseError);
    NSURL *controlURL = TLinkRemoteURL(url, @"/remote/device/control", nil);
    BOOL valid = enabled && licensed && controlURL && token.length >= 16;
    BOOL changed = ![_baseURL isEqualToString:url] || ![_token isEqualToString:token];
    if (!valid || changed) {
        [self disconnect];
        _baseURL = [url copy];
        _token = [token copy];
        _state = !enabled ? @"disabled" : (!licensed ? @"license_blocked" : @"invalid_configuration");
        _lastError = !licensed ? (licenseError ?: @"license_required") : @"";
    }
    if (valid && !_controlTask) [self connect];
    if (valid && _controlTask && _opened) [self sendPing];
    [self writeDiagnostics];
}

- (void)sendPing
{
    [_controlTask sendPingWithPongReceiveHandler:^(NSError *error) {
        if (!error) return;
        dispatch_async(self->_queue, ^{
            self->_lastError = error.localizedDescription ?: @"ping_failed";
            self->_state = @"disconnected";
            [self disconnect];
            [self writeDiagnostics];
        });
    }];
}

- (void)connect
{
    NSURL *url = TLinkRemoteURL(_baseURL, @"/remote/device/control", nil);
    NSMutableURLRequest *request = TLinkRemoteRequest(url, _token);
    if (!request) return;
    _deviceId = [self resolvedDeviceId];
    _state = @"connecting";
    _lastError = @"";
    _reconnectCount++;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.waitsForConnectivity = YES;
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    _controlTask = [_session webSocketTaskWithRequest:request];
    [_controlTask resume];
}

- (void)disconnect
{
    _opened = NO;
    for (TLinkRemoteVideoPump *pump in _videoPumps.allValues) [pump stop];
    [_videoPumps removeAllObjects];
    [_controlTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
    [_session invalidateAndCancel];
    _controlTask = nil;
    _session = nil;
}

- (void)URLSession:(NSURLSession *)session
     webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didOpenWithProtocol:(NSString *)protocol
{
    (void)session;
    (void)protocol;
    dispatch_async(_queue, ^{
        if (webSocketTask != self->_controlTask) return;
        self->_opened = YES;
        self->_state = @"connected";
        self->_lastError = @"";
        NSDictionary *hello = @{
            @"type": @"hello",
            @"device_id": self->_deviceId ?: @"",
            @"display_name": [UIDevice currentDevice].name ?: @"iPhone",
            @"system_name": [UIDevice currentDevice].systemName ?: @"iOS",
            @"system_version": [UIDevice currentDevice].systemVersion ?: @"",
            @"model": [UIDevice currentDevice].model ?: @"iPhone",
            @"service_version": @23,
        };
        [self sendJSON:hello];
        [self receiveNext];
        [self writeDiagnostics];
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    (void)session;
    dispatch_async(_queue, ^{
        if (task != self->_controlTask) return;
        self->_lastError = error.localizedDescription ?: @"connection_closed";
        self->_state = @"disconnected";
        [self disconnect];
        [self writeDiagnostics];
    });
}

- (void)sendJSON:(NSDictionary *)dictionary
{
    if (!_controlTask || !_opened) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!text) return;
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:text];
    [_controlTask sendMessage:message completionHandler:^(NSError *error) {
        if (!error) return;
        dispatch_async(self->_queue, ^{
            self->_lastError = error.localizedDescription ?: @"send_failed";
            [self disconnect];
            [self writeDiagnostics];
        });
    }];
}

- (void)receiveNext
{
    if (!_controlTask || !_opened) return;
    [_controlTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        dispatch_async(self->_queue, ^{
            if (error || !message) {
                self->_lastError = error.localizedDescription ?: @"receive_failed";
                self->_state = @"disconnected";
                [self disconnect];
                [self writeDiagnostics];
                return;
            }
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                NSData *data = [message.string dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if ([json isKindOfClass:[NSDictionary class]]) [self handleMessage:json];
            }
            [self receiveNext];
        });
    }];
}

- (void)handleMessage:(NSDictionary *)message
{
    NSString *type = [message[@"type"] isKindOfClass:[NSString class]] ? message[@"type"] : @"";
    if ([type isEqualToString:@"task"]) {
        uint64_t requestId = [message[@"request_id"] unsignedLongLongValue];
        BOOL expectsResponse = [message[@"expect_response"] boolValue];
        NSString *payload = [message[@"payload_b64"] isKindOfClass:[NSString class]] ? message[@"payload_b64"] : @"";
        NSData *line = [[NSData alloc] initWithBase64EncodedString:payload options:0];
        if (!line) {
            if (expectsResponse) [self sendTaskResult:requestId data:[@"-1;;invalid_remote_task_base64\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *response = TLinkDispatchTaskLineData(line);
            if (expectsResponse) {
                NSData *finalResponse = response ?: [@"-1;;empty_task_response\r\n" dataUsingEncoding:NSUTF8StringEncoding];
                dispatch_async(self->_queue, ^{ [self sendTaskResult:requestId data:finalResponse]; });
            }
        });
        return;
    }
    if ([type isEqualToString:@"video_start"]) {
        NSString *streamId = [message[@"stream_id"] isKindOfClass:[NSString class]] ? message[@"stream_id"] : @"";
        NSString *profile = [message[@"profile"] isKindOfClass:[NSString class]] ? message[@"profile"] : @"wan";
        if (streamId.length == 0) return;
        [_videoPumps[streamId] stop];
        TLinkRemoteVideoPump *pump = [[TLinkRemoteVideoPump alloc] initWithBaseURL:_baseURL
                                                                            token:_token
                                                                         deviceId:_deviceId
                                                                         streamId:streamId
                                                                          profile:profile];
        _videoPumps[streamId] = pump;
        [pump start];
        [self writeDiagnostics];
        return;
    }
    if ([type isEqualToString:@"video_stop"]) {
        NSString *streamId = [message[@"stream_id"] isKindOfClass:[NSString class]] ? message[@"stream_id"] : @"";
        [_videoPumps[streamId] stop];
        [_videoPumps removeObjectForKey:streamId];
        [self writeDiagnostics];
    }
}

- (void)sendTaskResult:(uint64_t)requestId data:(NSData *)data
{
    [self sendJSON:@{
        @"type": @"task_result",
        @"request_id": @(requestId),
        @"payload_b64": [data base64EncodedStringWithOptions:0] ?: @"",
    }];
}

@end

void TLinkStartRemoteBridgeAgent(void)
{
    static TLinkRemoteBridgeAgent *agent = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        agent = [[TLinkRemoteBridgeAgent alloc] init];
        [agent start];
    });
}
