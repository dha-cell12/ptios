#ifndef TLinkautoD_SOCKET_SERVER_H
#define TLinkautoD_SOCKET_SERVER_H

#import <Foundation/Foundation.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#define TLinkautoD_PORT 6000
#define TLinkautoD_ADDR "0.0.0.0"

void socketServer();

#endif
