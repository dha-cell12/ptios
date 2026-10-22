#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <cassert>
#include <atomic>
#include <cctype>
#include <cstdarg>
#include <cstring>
#include <cstdio>
#include <string>
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkSocketOutput.h"
#include "../shared/TLinkIPCPolicy.h"
#import "../shared/TLinkEventChannel.h"
#include "../pccontrol/IPCConstants.h"
#include "../pccontrol/SocketServer.h"
#define TLinkautoD_ADDR "0.0.0.0"
#define TLinkautoD_PORT 6000
static NSMutableDictionary *socketClients;
#include "SocketContextUnderTest.inc"
#include "SocketConstantsUnderTest.inc"
#include "SocketGlobalsUnderTest.inc"
static void zx_processClientBuffer(ZXClientContext *ctx);
static void zx_rearmOutput();
static void zx_writeAll(CFWriteStreamRef, NSData *);
static NSDictionary *zx_jsonResponseFromLegacy(NSData *, NSNumber *);
static NSData *zx_frameJSONResponse(NSDictionary *);
static void zx_logf(const char *, ...) {}
static NSData *zx_dataFromCString(const char *s) { return s ? [NSData dataWithBytes:s length:strlen(s)] : nil; }
static BOOL TLinkRootfullLicenseTaskAllowed(int, NSString **) { return true; }
static dispatch_semaphore_t taskStarted, taskFinish;
static NSMutableArray *taskCalls;
static NSData *zx_handleLegacyRequestBytes(const char *payload) {
    NSString *s = [NSString stringWithUTF8String:payload];
    @synchronized(taskCalls) { [taskCalls addObject:s]; }
    if ([s isEqualToString:@"99slow"]) { dispatch_semaphore_signal(taskStarted); dispatch_semaphore_wait(taskFinish, DISPATCH_TIME_FOREVER); }
    if ([s isEqualToString:@"69wait"]) {
        assert(TLinkCurrentNativeBudget()&&TLinkCurrentNativeBudget()->deadline());
        dispatch_semaphore_signal(taskStarted);assert(!TLinkNativeWaitNs(20000000000ULL));
    }
    if ([s isEqualToString:@"48large"]) return [NSMutableData dataWithLength:1024 * 1024 + 1];
    return [[NSString stringWithFormat:@"0;;%@\r\n", s] dataUsingEncoding:NSUTF8StringEncoding];
}
#include "SocketQueueUnderTest.inc"
#include "SocketCleanupUnderTest.inc"
// Deterministic monotonic clock boundary; production uses TLinkNativeNowNs.
static std::atomic<uint64_t> socketClock(0);
static uint64_t zx_socketNowMs() { return socketClock.load(std::memory_order_acquire); }
#include "SocketOutputUnderTest.inc"
#include "SocketJSONUnderTest.inc"
#include "SocketPollUnderTest.inc"
#include "SocketWorkUnderTest.inc"
#include "SocketTaskTypeUnderTest.inc"
#include "SocketParserUnderTest.inc"
#include "SocketReadUnderTest.inc"
#include "SocketAcceptUnderTest.inc"
static size_t ipcTaskCalls = 0, ipcLogs = 0, ipcLength = 0;
static bool ipcNullStream = false;
static uint64_t ipcDeadline=0;
static void processTaskWithContext(UInt8 *bytes, size_t n, CFWriteStreamRef stream, id) {
    ipcDeadline=TLinkCurrentNativeBudget()?TLinkCurrentNativeBudget()->deadline():0;
    ++ipcTaskCalls; ipcLength = n; ipcNullStream = !stream;
    if (n >= 5 && memcmp(bytes, "48big", 5) == 0) {
        std::string huge(1024 * 1024 + 1, 'x'); notifyClient((UInt8 *)huge.c_str(), stream);
    } else if (n >= 2 && memcmp(bytes, "61", 2) == 0) notifyClient((UInt8 *)"0;;7;;123\r\n", stream);
}
static void sendHardwareKeyEventFromRawData(UInt8 *, NSError **) {}
// Preserve NSLog argument evaluation and format checking, including elapsed time.
static NSMutableArray<NSString *> *ipcLogMessages;
static void captureIPCLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void captureIPCLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    ++ipcLogs;
    [ipcLogMessages addObject:message];
}
#define NSLog(...) captureIPCLog(__VA_ARGS__)
#include "IPCHandlerUnderTest.inc"
#undef NSLog
static void ipcFixtures() {
    ipcLogMessages = [NSMutableArray array];
    (void)kTLinkautoIPCPortName; (void)kTLinkautoIPCReadyMarkerPath; (void)kTLinkautoTweakLoadedMarkerPath;
    const uint8_t exact[] = {'T','A','S','K',':',':','1','0'};
    CFDataRef input = CFDataCreate(nullptr, exact, sizeof(exact));
    assert(!handleIPCMessage(nullptr, 2, input, nullptr)); CFRelease(input);
    assert(ipcTaskCalls == 1 && ipcLength == 2 && ipcNullStream && !ipcLogs);
    auto request = [](const char *s) -> NSString * {
        CFDataRef data = CFDataCreate(nullptr, (const UInt8 *)s, strlen(s));
        CFDataRef result = handleIPCMessage(nullptr, 1, data, nullptr); CFRelease(data);
        assert(result); NSData *owned = CFBridgingRelease(result);
        return [[NSString alloc] initWithData:owned encoding:NSUTF8StringEncoding];
    };
    assert([request("TASK::61sequence") isEqualToString:@"0;;7;;123\r\n"] && !ipcLogs);
    assert([request("TASK::48big") isEqualToString:@"1;;ipc_response_too_large\r\n"]);
    const size_t previousLogs = ipcLogs;
    assert([request("TASK::77private-selector") isEqualToString:@"0\r\n"]);
    assert(ipcLogs == previousLogs + 2);
    assert([ipcLogMessages.lastObject containsString:@"IPC UI tree task=77 response in "]);
    assert([ipcLogMessages.lastObject hasSuffix:@"bytes=0"]);
    for (NSString *message in ipcLogMessages) assert(![message containsString:@"private-selector"]);
    const char *payload="TASK::69fixture";const uint64_t deadline=TLinkNativeDeadline(1);
    auto encoded=TLinkC01Encode((const uint8_t *)payload,strlen(payload),deadline);
    auto bounded=[&](const std::vector<uint8_t> &bytes)->NSString *{
        CFDataRef data=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size()));
        CFDataRef reply=handleIPCMessage(NULL,TLinkC01IPCMessage,data,NULL);CFRelease(data);assert(reply);
        NSData *owned=CFBridgingRelease(reply);return [[NSString alloc] initWithData:owned encoding:NSUTF8StringEncoding];
    };
    const size_t previousCalls=ipcTaskCalls;
    assert([bounded(encoded) isEqualToString:@"0\r\n"]&&ipcDeadline==deadline&&ipcTaskCalls==previousCalls+1);
    encoded=TLinkC01Encode((const uint8_t *)payload,strlen(payload),TLinkNativeNowNs()-1);
    assert([bounded(encoded) containsString:@"c01_request_expired"]&&ipcTaskCalls==previousCalls+1);
    encoded[0]^=1;assert([bounded(encoded) containsString:@"c01_ipc_envelope_invalid"]&&ipcTaskCalls==previousCalls+1);

}
static ZXClientContext *client(int *peer) {
    int pair[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    int one = 1, size = 1024;
    assert(setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) == 0);
    assert(setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size)) == 0);
    CFReadStreamRef read = nullptr; CFWriteStreamRef write = nullptr;
    CFStreamCreatePairWithSocket(nullptr, pair[0], &read, &write); assert(read && write);
    CFReadStreamSetProperty(read, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(write, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    assert(CFReadStreamOpen(read) && CFWriteStreamOpen(write));
    ZXClientContext *ctx = [ZXClientContext new]; ctx.readStream = read; ctx.writeStream = write;
    ctx.runLoop = CFRunLoopGetCurrent(); ctx.nativeSocket = pair[0]; ctx.buffer = [NSMutableData data];
    ctx->closed.store(false); ctx.protocol = ZXWireProtocolUnknown;
    dispatch_sync(socketQueue(), ^{ socketClients[@((long)read)] = ctx; });
    *peer = pair[1]; return ctx;
}
static void feed(ZXClientContext *ctx, NSData *data) {
    dispatch_sync(socketQueue(), ^{ [ctx.buffer appendData:data]; zx_processClientBuffer(ctx); });
}
static NSData *text(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *receive(int fd) {
    NSMutableData *result = [NSMutableData data]; uint8_t bytes[65536];
    for (;;) { ssize_t n = recv(fd, bytes, sizeof(bytes), MSG_DONTWAIT); if (n <= 0) break; [result appendBytes:bytes length:(NSUInteger)n]; }
    return result;
}
static void drainTasks(unsigned turns = 4) {
    for (unsigned n = 0; n < turns; ++n) { dispatch_sync(zx_taskQueue(), ^{}); dispatch_sync(socketQueue(), ^{}); }
}
static void dispose(ZXClientContext *ctx, int fd) { dispatch_sync(socketQueue(), ^{ zx_cleanupClient(ctx.readStream); }); close(fd); }
int main() {
 @autoreleasepool {
    fputs("Socket runtime: bounded IPC/no-reply/ACK\n", stderr); ipcFixtures();
    (void)&TCPServerAcceptCallBack;
    socketClients = [NSMutableDictionary dictionary]; taskCalls = [NSMutableArray array];
    taskStarted = dispatch_semaphore_create(0); taskFinish = dispatch_semaphore_create(0);
    fputs("Socket runtime: actual eight deferred polls cancel through production cleanup\n",stderr);
    NSMutableArray *eventClients = [NSMutableArray array]; std::vector<int> eventPeers;
    for (unsigned n = 0; n < 8; ++n) { int peer; ZXClientContext *event = client(&peer); [eventClients addObject:event]; eventPeers.push_back(peer); feed(event,text(@"950;;25000;;8;;*\n")); }
    for (unsigned n = 0; n < 8; ++n) {
        ZXClientContext *event = eventClients[n]; TLinkEventPollRequest *request = event.eventPollRequest;
        dispose(event,eventPeers[n]); assert(request.isCancelled && !event.eventPollRequest && !event.eventPollPending);
    }
    assert([TLinkEventChannelStatus()[@"active_polls"] intValue] == 0);
    int aPeer, bPeer; ZXClientContext *a = client(&aPeer), *b = client(&bPeer);
    fputs("Socket runtime: FIFO work and independent daemon ping\n", stderr);
    feed(a, text(@"99slow\n60next\n"));
    assert(dispatch_semaphore_wait(taskStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    feed(b, text(@"CMD_PING\n"));
    assert([[[NSString alloc] initWithData:receive(bPeer) encoding:NSUTF8StringEncoding] isEqualToString:@"0;;daemon\r\n"]);
    @synchronized(taskCalls) { assert(taskCalls.count == 1); }
    dispatch_semaphore_signal(taskFinish); drainTasks();
    NSString *ordered = [[NSString alloc] initWithData:receive(aPeer) encoding:NSUTF8StringEncoding];
    assert([ordered isEqualToString:@"0;;99slow\r\n0;;60next\r\n"]);
    fputs("Socket runtime: C01 deadline starts before queue, plus disconnect cancellation\n",stderr);
    feed(a,text(@"99slow\n"));assert(dispatch_semaphore_wait(taskStarted,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    feed(b,text(@"69expired\n"));
    dispatch_semaphore_t age=dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3100*NSEC_PER_MSEC),dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{dispatch_semaphore_signal(age);});
    assert(dispatch_semaphore_wait(age,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    dispatch_semaphore_signal(taskFinish);drainTasks();
    @synchronized(taskCalls){assert(![taskCalls containsObject:@"69expired"]);}
    NSString *expiredReply=[[NSString alloc] initWithData:receive(bPeer) encoding:NSUTF8StringEncoding];assert([expiredReply isEqualToString:@"1;;c01_request_expired\r\n"]);(void)receive(aPeer);
    int cancelPeer;ZXClientContext *cancelClient=client(&cancelPeer);feed(cancelClient,text(@"69wait\n"));
    assert(dispatch_semaphore_wait(taskStarted,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    auto cancellation=cancelClient->c01Cancellation;assert(cancellation);dispose(cancelClient,cancelPeer);drainTasks();assert(cancellation->cancelled());
    // Actual JSON parser/frame encoder and explicit oversized-result fallback.
    int jsonPeer; ZXClientContext *jsonClient = client(&jsonPeer);
    feed(jsonClient, zx_frameJSONResponse(@{@"id": @42, @"task": @48, @"args": @[@"large"]}));
    drainTasks(); NSData *framed = receive(jsonPeer); assert(framed.length > 10);
    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[framed subdataWithRange:NSMakeRange(10, framed.length - 10)] options:0 error:NULL];
    assert([obj[@"id"] isEqual:@42] && ![obj[@"ok"] boolValue] && [obj[@"error"] isEqual:@"response_too_large"]);
    feed(jsonClient, zx_frameJSONResponse(@{@"id": @43, @"task": @10, @"args": @[@"touch"]}));
    drainTasks(); assert(receive(jsonPeer).length == 0);
    feed(jsonClient, zx_frameJSONResponse(@{@"id": @44, @"task": @61, @"args": @[@"ack"]}));
    drainTasks(); framed = receive(jsonPeer); assert(framed.length > 10);
    obj = [NSJSONSerialization JSONObjectWithData:[framed subdataWithRange:NSMakeRange(10, framed.length - 10)] options:0 error:NULL];
    assert([obj[@"id"] isEqual:@44] && [obj[@"ok"] boolValue]);
    dispose(jsonClient, jsonPeer);
    // Force real send backpressure; another client's output must still progress.
    fputs("Socket runtime: actual nonblocking sends under backpressure\n", stderr);
    NSMutableData *large = [NSMutableData dataWithLength:200000]; memset(large.mutableBytes, 0x5a, large.length);
    dispatch_sync(socketQueue(), ^{ zx_writeAll(a.writeStream, large); assert(!a->output.empty()); zx_writeAll(b.writeStream, text(@"alive")); });
    assert(receive(bPeer).length == 5);
    NSMutableData *received = [NSMutableData data];
    for (unsigned n = 0; n < 1000 && received.length < large.length; ++n) {
        [received appendData:receive(aPeer)]; dispatch_sync(socketQueue(), ^{ zx_flushOutput(a); });
    }
    [received appendData:receive(aPeer)]; assert([received isEqualToData:large]);
    // Constant traffic must not postpone the service timer until after it goes quiet.
    fputs("Socket runtime: no-progress deadline under continuous other-client traffic\n", stderr);
    dispatch_semaphore_t timedOut = dispatch_semaphore_create(0);
    __block dispatch_source_t traffic = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, socketQueue());
    dispatch_sync(socketQueue(), ^{
        zx_writeAll(a.writeStream, large); assert(!a->output.empty()); socketClock.store(5000);
        dispatch_source_set_event_handler(traffic, ^{
            zx_writeAll(b.writeStream, text(@"ping"));
            if (a->closed.load()) { dispatch_source_cancel(traffic); dispatch_semaphore_signal(timedOut); }
        });
        dispatch_source_set_timer(traffic, DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC, 0); dispatch_resume(traffic);
    });
    assert(dispatch_semaphore_wait(timedOut, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    dispatch_sync(socketQueue(), ^{ dispatch_source_set_event_handler(traffic, ^{}); traffic = nil; });
    (void)receive(bPeer); close(aPeer); a = client(&aPeer);
    // Disconnect queued work while an admitted task is blocked; skip the canceled client.
    feed(a, text(@"99slow\n")); assert(dispatch_semaphore_wait(taskStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    feed(b, text(@"60cancelled\n")); dispose(b, bPeer);
    dispatch_semaphore_signal(taskFinish); drainTasks();
    @synchronized(taskCalls) { assert(![taskCalls containsObject:@"60cancelled"]); }
    (void)receive(aPeer); dispose(a, aPeer);
    fputs("Socket runtime: bounded work admission and queued disconnect\n", stderr);
    NSMutableArray *limited = [NSMutableArray array]; std::vector<int> peers;
    for (unsigned n = 0; n < 17; ++n) { int fd; [limited addObject:client(&fd)]; peers.push_back(fd); }
    feed(limited[0], text(@"99slow\n"));
    assert(dispatch_semaphore_wait(taskStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    for (unsigned n = 1; n < 17; ++n) feed(limited[n], text(@"60bounded\n"));
    dispatch_sync(socketQueue(), ^{ ZXClientContext *rejected = limited[16]; assert(gPendingTasks == 16 && rejected->closed.load()); });
    dispatch_semaphore_signal(taskFinish); drainTasks(20);
    for (unsigned n = 0; n < 17; ++n) dispose(limited[n], peers[n]);
    // Output failure closes cleanly and stale queued read events retain their CF object.
    a = client(&aPeer); close(aPeer);
    dispatch_sync(socketQueue(), ^{ zx_writeAll(a.writeStream, text(@"closed")); assert(a->closed.load()); });
    b = client(&bPeer);
    dispatch_sync(socketQueue(), ^{ readStream(b.readStream, kCFStreamEventEndEncountered, nullptr); readStream(b.readStream, kCFStreamEventEndEncountered, nullptr); });
    dispatch_sync(socketQueue(), ^{}); close(bPeer);
    dispatch_sync(socketQueue(), ^{
        assert(!socketClients.count && !gOutputBytes && !gPendingTasks);
        if (gOutputTimer) { dispatch_source_cancel(gOutputTimer); gOutputTimer = nil; }
    });
    puts("Socket runtime passed: actual IPC callback, parser, FIFO work, disconnect, nonblocking output, JSON errors and stale read cleanup.");
 }
}
