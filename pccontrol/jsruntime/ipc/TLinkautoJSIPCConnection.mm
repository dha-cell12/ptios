#import "TLinkautoJSIPCConnection.h"
#import "TLinkautoJSIPCCodec.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>

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
    chmod([_socketPath UTF8String], 0660);

    if (listen(_listenFd, 1) < 0) {
        close(_listenFd);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int clientFd = accept(self->_listenFd, NULL, NULL);
        if (clientFd >= 0) {
            dispatch_async(self->_ioQueue, ^{
                [self handleNewClient:clientFd];
            });
        }
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
        // In real impl, we should schedule a retry
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

- (void)readData {
    // Read header
    TLinkautoJSIPCHeader header;
    ssize_t bytesRead = read(_clientFd, &header, sizeof(header));

    if (bytesRead <= 0) {
        [self stop];
        return;
    }

    if (bytesRead < sizeof(header)) {
        // Handle fragmentation in real impl. Keeping it simple.
        [self stop];
        return;
    }

    if (header.magic != TLJS_MAGIC || header.version != TLJS_VERSION || header.payloadLength > 1024*1024) {
        [self stop];
        return;
    }

    NSDictionary *payload = @{};
    if (header.payloadLength > 0) {
        NSMutableData *payloadData = [NSMutableData dataWithLength:header.payloadLength];
        ssize_t payloadRead = read(_clientFd, payloadData.mutableBytes, header.payloadLength);
        if (payloadRead == header.payloadLength) {
            payload = [TLinkautoJSIPCCodec decodePayload:payloadData error:nil] ?: @{};
        } else {
            [self stop];
            return;
        }
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
            write(self->_clientFd, packet.bytes, packet.length);
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
    });
}

@end
