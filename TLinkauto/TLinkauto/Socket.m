//
//  Socket.m
//  TLinkauto
//
//  Created by Jason on 2020/12/11.
//

#import "Socket.h"
#import "TLinkAppDiagnostic.h"


@implementation Socket
{
    int socketHandle;
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
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    // Convert IPv4 and IPv6 addresses from text to binary form
    if(inet_pton(AF_INET, [ip UTF8String], &serv_addr.sin_addr)<=0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: Invalid address. Address not supported");
        APP_DIAG("SOCKET-ERROR", "inet_pton() failed for %s", [ip UTF8String]);
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: \nConnection Failed \n");
        APP_DIAG("SOCKET-ERROR", "connect() failed errno=%d", errno);
        return -1;
    }
    socketHandle = sock;
    return 0;
}

-(BOOL) isConnected {
    return socketHandle != 0;
}

-(void) send: (NSString*)msg
{
    const char *buffer = [msg UTF8String];
    size_t len = strlen(buffer);
    ssize_t sent = send(socketHandle , buffer, len , 0);
    if (sent < 0) {
        APP_DIAG("SOCKET-ERROR", "send() failed errno=%d", errno);
    }
}

-(void) sendChar: (char*)msg
{
    send(socketHandle , msg, strlen(msg) , 0);
}

-(NSString*) recv:(int)length
{
    char buffer[length];
    memset(buffer, 0, sizeof(buffer));
    ssize_t received = recv(socketHandle, buffer, length, 0);
    if (received < 0) {
        APP_DIAG("SOCKET-ERROR", "recv() failed errno=%d", errno);
    }
    return [NSString stringWithUTF8String:buffer];
}

-(void)close {
    if (!socketHandle)
        return;
    close(socketHandle);
    socketHandle = 0;
}

-(void)dealloc {
    [self close];
}

@end
