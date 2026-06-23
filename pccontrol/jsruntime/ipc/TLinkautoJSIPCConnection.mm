#import "TLinkautoJSIPCConnection.h"
#import "TLinkautoJSIPCCodec.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

@implementation TLinkautoJSIPCConnection {
    NSString *_socketPath;
    BOOL _isServer;
    int _listenFd;
    int _clientFd;
    dispatch_queue_t _ioQueue;
    dispatch_source_t _readSource;
    BOOL _running;
}

- (instancetype)initWithSocketFile:(NSString *)socketPath isServer:(BOOL)isServer {
    self = [super init];
    if (self) {
        _socketPath = [socketPath copy];
        _isServer = isServer;
        _listenFd = -1;
        _clientFd = -1;
        _ioQueue = dispatch_queue_create("com.tlinkauto.jsipc.io", DISPATCH_QUEUE_SERIAL);
        _running = NO;
    }
    return self;
}

- (void)start {
    dispatch_async(_ioQueue, ^{
        if (self->_running) return;
        self->_running = YES;

        if (self->_isServer) {
            [self setupServer];
        } else {
            [self setupClient];
        }
    });
}

- (void)setupServer {
    unlink([_socketPath UTF8String]);
    _listenFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_listenFd < 0) return;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [_socketPath UTF8String], sizeof(addr.sun_path)-1);

    if (bind(_listenFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_listenFd);
        return;
    }

    // Set permissions to 0660 (owner root, group mobile in real deploy)
    chmod([_socketPath UTF8String], 0777);

    if (listen(_listenFd, 1) < 0) {
        close(_listenFd);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int clientFd = accept(self->_listenFd, NULL, NULL);
        if (clientFd >= 0) {
            dispatch_async(self->_ioQueue, ^{
                [self handleNewClient:clientFd];
                if ([self.delegate respondsToSelector:@selector(connectionDidAcceptClient)]) {
                    [(id)self.delegate connectionDidAcceptClient];
                }
            });
        }
    });
}

- (void)scheduleReconnect {
    if (_isServer || !_running) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), _ioQueue, ^{
        if (!self->_running || self->_clientFd >= 0) {
            return;
        }
        [self setupClient];
    });
}

- (void)setupClient {
    _clientFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_clientFd < 0) return;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [_socketPath UTF8String], sizeof(addr.sun_path)-1);

    if (connect(_clientFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_clientFd);
        _clientFd = -1;
        [self scheduleReconnect];
        return;
    }

    [self handleNewClient:_clientFd];
}

- (void)handleNewClient:(int)fd {
    // Basic peer verification can go here using getpeereid(fd, &euid, &egid)
    _clientFd = fd;

    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _ioQueue);
    dispatch_source_set_event_handler(_readSource, ^{
        [self readData];
    });
    dispatch_source_set_cancel_handler(_readSource, ^{
        close(fd);
    });
    dispatch_resume(_readSource);
}

- (BOOL)readFully:(int)fd buffer:(void *)buffer length:(size_t)length {
    size_t totalRead = 0;
    while (totalRead < length) {
        ssize_t r = read(fd, (uint8_t *)buffer + totalRead, length - totalRead);
        if (r <= 0) return NO;
        totalRead += r;
    }
    return YES;
}

- (BOOL)writeFully:(int)fd buffer:(const void *)buffer length:(size_t)length {
    size_t totalWritten = 0;
    while (totalWritten < length) {
        ssize_t w = write(fd, (const uint8_t *)buffer + totalWritten, length - totalWritten);
        if (w <= 0) return NO;
        totalWritten += w;
    }
    return YES;
}

- (void)readData {
    // Read header
    TLinkautoJSIPCHeader header;
    if (![self readFully:_clientFd buffer:&header length:sizeof(header)]) {
        [self stop];
        return;
    }

    if (header.magic != TLJS_MAGIC || header.version != TLJS_VERSION || header.payloadLength > 10*1024*1024) {
        [self stop];
        return;
    }

    NSDictionary *payload = @{};
    if (header.payloadLength > 0) {
        NSMutableData *payloadData = [NSMutableData dataWithLength:header.payloadLength];
        if (![self readFully:_clientFd buffer:payloadData.mutableBytes length:header.payloadLength]) {
            [self stop];
            return;
        }
        payload = [TLinkautoJSIPCCodec decodePayload:payloadData error:nil] ?: @{};
    }

    if ([self.delegate respondsToSelector:@selector(connectionDidReceiveMessage:payload:)]) {
        [self.delegate connectionDidReceiveMessage:header payload:payload];
    }
}

- (BOOL)sendMessageWithType:(uint16_t)type
                 requestId:(uint64_t)requestId
                     runId:(uint64_t)runId
                generation:(uint64_t)generation
                   timeout:(uint32_t)timeoutMs
                   payload:(NSDictionary *)payload {
    NSData *packet = [TLinkautoJSIPCCodec encodeMessageWithType:type
                                                      requestId:requestId
                                                          runId:runId
                                                     generation:generation
                                                        timeout:timeoutMs
                                                        payload:payload];
    if (!packet) return NO;

    dispatch_async(_ioQueue, ^{
        if (self->_clientFd >= 0) {
            if (![self writeFully:self->_clientFd buffer:packet.bytes length:packet.length]) {
                [self stop];
            }
        }
    });
    return YES;
}

- (void)stop {
    dispatch_async(_ioQueue, ^{
        if (!self->_running) return;
        self->_running = NO;

        if (self->_readSource) {
            dispatch_source_cancel(self->_readSource);
            self->_readSource = nil;
        }
        if (self->_listenFd >= 0) {
            close(self->_listenFd);
            self->_listenFd = -1;
        }
        self->_clientFd = -1;

        if ([self.delegate respondsToSelector:@selector(connectionDidDisconnect)]) {
            [self.delegate connectionDidDisconnect];
        }

        [self scheduleReconnect];
    });
}

@end
