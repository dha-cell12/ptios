//
//  Socket.m
//  TLinkauto
//
//  Created by Jason on 2020/12/11.
//

#import "Socket.h"
#import "TLinkAppDiagnostic.h"
#include <errno.h>
#include <sys/time.h>


@implementation Socket
{
    int socketHandle;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        socketHandle = -1;
    }
    return self;
}

/**
 Connect to a server, return -1 if fail
 */
-(int) connect: (NSString*) ip byPort:(int) port
{
    //NSLog(@"ip: %@, and port: %d", ip, port);
    int sock = 0;
    struct sockaddr_in serv_addr;

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob:  Socket creation error");
        APP_DIAG("SOCKET-ERROR", "socket() failed errno=%d", errno);
        return -1;
        
    }

    // UI callers must never wait forever when the daemon is unavailable or
    // when a legacy task intentionally does not return a response.
    struct timeval timeout;
    timeout.tv_sec = 2;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    // Convert IPv4 and IPv6 addresses from text to binary form
    if(inet_pton(AF_INET, [ip UTF8String], &serv_addr.sin_addr)<=0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: Invalid address. Address not supported");
        APP_DIAG("SOCKET-ERROR", "inet_pton() failed for %s", [ip UTF8String]);
        close(sock);
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: \nConnection Failed \n");
        APP_DIAG("SOCKET-ERROR", "connect() failed errno=%d", errno);
        close(sock);
        return -1;
    }
    socketHandle = sock;
    return 0;
}

-(BOOL) isConnected {
    return socketHandle >= 0;
}

-(void) send: (NSString*)msg
{
    if (![self isConnected] || !msg) {
        return;
    }

    const char *buffer = [msg UTF8String];
    size_t len = strlen(buffer);
    size_t offset = 0;
    while (offset < len) {
        ssize_t sent = send(socketHandle, buffer + offset, len - offset, 0);
        if (sent > 0) {
            offset += (size_t)sent;
            continue;
        }
        if (sent < 0 && errno == EINTR) {
            continue;
        }
        APP_DIAG("SOCKET-ERROR", "send() failed errno=%d sent=%zu total=%zu",
                 errno, offset, len);
        break;
    }
}

-(void) sendChar: (char*)msg
{
    if (msg) {
        [self send:[NSString stringWithUTF8String:msg]];
    }
}

-(NSString*) recv:(int)length
{
    if (![self isConnected] || length <= 0) {
        return @"";
    }

    char *buffer = (char *)calloc((size_t)length + 1, 1);
    if (!buffer) {
        APP_DIAG("SOCKET-ERROR", "recv() allocation failed length=%d", length);
        return @"";
    }

    ssize_t received = recv(socketHandle, buffer, (size_t)length, 0);
    if (received < 0) {
        APP_DIAG("SOCKET-ERROR", "recv() failed errno=%d", errno);
        free(buffer);
        return @"";
    }

    NSString *result = [[NSString alloc] initWithBytes:buffer
                                                length:(NSUInteger)received
                                              encoding:NSUTF8StringEncoding];
    free(buffer);
    return result ?: @"";
}

-(void)close {
    if (socketHandle < 0)
        return;
    close(socketHandle);
    socketHandle = -1;
}

-(void)dealloc {
    [self close];
}

@end
