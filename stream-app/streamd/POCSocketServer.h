#ifndef POC_SOCKET_SERVER_H
#define POC_SOCKET_SERVER_H

#import <Foundation/Foundation.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#define POC_SOCKET_PORT 6000
#define POC_SOCKET_ADDR "0.0.0.0"

#ifdef __cplusplus
extern "C" {
#endif

// Start the TLinkauto-compatible task server on its own background thread with
// a CFRunLoop. Safe to call once; subsequent calls are ignored.
void TLinkStartTaskServer(void);
void TLinkSetLaunchExecutablePath(const char *path);

// Dispatches one legacy task line in-process. Remote transports use this to
// share the exact same parser, license gates and response format as tcp/6000.
// Returns nil for legacy fire-and-forget task 10.
NSData *TLinkDispatchTaskLineData(NSData *lineData);

// Backward-compatible name kept while the source file is still being migrated
// from the original PoC naming.
void POCStartSocketServer(void);

// Runs one Vision request without starting the socket/video services. Used by
// streamd's isolated OCR worker mode so a Vision native crash cannot take down
// tcp/6000.
int TLinkRunVisionOCRWorker(const char *payloadBase64, const char *outputPath);
int TLinkRunTesseractOCRWorker(const char *payloadBase64, const char *outputPath);

#ifdef __cplusplus
}
#endif

#endif
