#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import "../pccontrol/SocketServer.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkIPCPolicy.h"
#include "../shared/TLinkCaptureLeasePOSIX.h"
#include "../shared/TLinkNativeDispatch.h"
#include "C01IPCConstants.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
static dispatch_semaphore_t entered,released,exited;
static std::atomic<unsigned> handlerCalls{0};
static CFDataRef handleC01IPCMessage(CFMessagePortRef,SInt32,CFDataRef,void *);
static NSString *take(CFDataRef reply){assert(reply);NSData *data=CFBridgingRelease(reply);return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
static void processTaskWithContext(UInt8 *bytes,size_t length,CFWriteStreamRef stream,id context){
    (void)context;++handlerCalls;
    NSString *wire=[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];assert(wire);
    if([wire hasSuffix:@"hold"]){dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(released,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if([wire isEqualToString:@"69objcThrow"])@throw [NSException exceptionWithName:@"Fixture" reason:@"controlled failure" userInfo:nil];
    if([wire isEqualToString:@"69cppThrow"])throw std::runtime_error("controlled failure");
    if([wire isEqualToString:@"69nested"]){
        const char *payload="TASK::69nestedInner";auto bytes=TLinkC01Encode((const uint8_t *)payload,strlen(payload),TLinkNativeDeadline(2));
        CFDataRef request=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size()));
        assert([take(handleC01IPCMessage(NULL,TLinkC01IPCMessage,request,NULL)) containsString:@"c01_ipc_busy"]);CFRelease(request);
    }
    NSString *reply=[NSString stringWithFormat:@"0;;%@\r\n",wire];notifyClient((UInt8 *)reply.UTF8String,stream);
    if([wire hasSuffix:@"hold"])dispatch_semaphore_signal(exited);
}
static void sendHardwareKeyEventFromRawData(UInt8 *,NSError **) {assert(false);}
#include "C01IPCHandler.inc"
static bool failSource=false;
static CFRunLoopSourceRef FixtureSource(CFAllocatorRef allocator,CFMessagePortRef port,CFIndex order){
    return failSource?NULL:CFMessagePortCreateRunLoopSource(allocator,port,order);
}
#define CFMessagePortCreateRunLoopSource FixtureSource
#include "C01IPCReceiver.inc"
#undef CFMessagePortCreateRunLoopSource
#include "C01IPCQueues.inc"
static bool zx_isHotPathPayload(const char *){return true;}
#include "C01IPCSenderActual.inc"
// The actual installation function is run on a controllable owner thread so
// the harness can stop/join each real CF run loop and balance all CF objects.
class Server {
    std::thread thread_;
    CFRunLoopRef loop_=NULL;
public:
    Server(CFStringRef name,bool isolated){
        auto ready=dispatch_semaphore_create(0);
        thread_=std::thread([this,name,isolated,ready]{@autoreleasepool{
            CFMessagePortRef port=NULL;CFRunLoopSourceRef source=NULL;
            if(isolated)assert(zx_installC01IPCSource(name,&port,&source));
            else{
                CFMessagePortContext context={0,NULL,NULL,NULL,NULL};Boolean shouldFree=false;
                port=CFMessagePortCreateLocal(NULL,name,handleIPCMessage,&context,&shouldFree);assert(port);
                source=CFMessagePortCreateRunLoopSource(NULL,port,0);assert(source);
                CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopCommonModes);
            }
            loop_=CFRunLoopGetCurrent();CFRetain(loop_);dispatch_semaphore_signal(ready);CFRunLoopRun();
            CFRunLoopRemoveSource(loop_,source,kCFRunLoopCommonModes);CFRelease(source);CFMessagePortInvalidate(port);CFRelease(port);CFRelease(loop_);
        }});
        assert(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    }
    void stop(){if(thread_.joinable()){CFRunLoopRef loop=loop_;CFRetain(loop);CFRunLoopStop(loop);CFRunLoopWakeUp(loop);thread_.join();CFRelease(loop);loop_=NULL;}}
    ~Server(){stop();}
    Server(const Server &)=delete;Server &operator=(const Server &)=delete;
};
static CFDataRef invoke(const char *payload,double seconds=0){
    TLinkNativeBudgetPtr budget;
    if(seconds)budget=std::make_shared<TLinkNativeBudget>(TLinkNativeDeadline(seconds),TLinkNativeBudgetPtr{});
    TLinkNativeBudgetScope scope(budget);__block CFDataRef response=NULL;
    TLinkNativeDispatchSync(zx_ipcRequestQueue(payload,true),^{response=sendIPCMessage(payload,true);});return response;
}
static NSString *rawPrivate(SInt32 messageID,const std::vector<uint8_t> &bytes){
    CFMessagePortRef port=CFMessagePortCreateRemote(NULL,kTLinkautoC01IPCPortName);assert(port);
    CFDataRef request=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size())),reply=NULL;
    assert(CFMessagePortSendRequest(port,messageID,request,.2,.5,kCFRunLoopDefaultMode,&reply)==kCFMessagePortSuccess);
    CFRelease(request);CFRelease(port);return take(reply);
}
static void startHold(const char *payload,double timeout,std::thread &sender,NSString *__strong *reply){
    entered=dispatch_semaphore_create(0);released=dispatch_semaphore_create(0);exited=dispatch_semaphore_create(0);
    sender=std::thread([payload,timeout,reply]{@autoreleasepool{*reply=take(invoke(payload,timeout));}});
    assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
}
static void finishHold(std::thread &sender){
    dispatch_semaphore_signal(released);sender.join();assert(dispatch_semaphore_wait(exited,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
}
int main(){@autoreleasepool{
    // Failed source creation must invalidate/release the registered port.
    CFMessagePortRef failedPort=NULL;CFRunLoopSourceRef failedSource=NULL;failSource=true;
    assert(!zx_installC01IPCSource(kTLinkautoC01IPCPortName,&failedPort,&failedSource)&&!failedPort&&!failedSource);failSource=false;
    CFMessagePortRef absent=CFMessagePortCreateRemote(NULL,kTLinkautoC01IPCPortName);assert(!absent);
    Server legacy(kTLinkautoIPCPortName,false);Server isolated(kTLinkautoC01IPCPortName,true);
    assert([take(invoke("TASK::61warm")) isEqualToString:@"0;;61warm\r\n"]);
    assert([take(invoke("TASK::69warm",3)) isEqualToString:@"0;;69warm\r\n"]);
    {
        TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(TLinkNativeDeadline(3),TLinkNativeBudgetPtr{}));
        assert(zx_ipcRequestQueue("TASK::69probe",true)!=ipcQueue());
        assert(zx_ipcRequestQueue("TASK::10probe",false)==ipcQueue());
        assert(zx_ipcRequestQueue("TASK::61probe",true)==ipcQueue());
    }
    // Both real receiver owner threads progress while the other port is blocked.
    std::thread sender;NSString *heldReply=nil;
    startHold("TASK::61hold",0,sender,&heldReply);
    assert([take(invoke("TASK::69duringLegacyHold",3)) isEqualToString:@"0;;69duringLegacyHold\r\n"]);
    finishHold(sender);assert([heldReply isEqualToString:@"0;;61hold\r\n"]);
    startHold("TASK::69hold",3,sender,&heldReply);
    assert([take(invoke("TASK::61duringImageHold")) isEqualToString:@"0;;61duringImageHold\r\n"]);
    finishHold(sender);assert([heldReply isEqualToString:@"0;;69hold\r\n"]);
    // Sender returns on transport timeout while receiver still owns its callback.
    // Ordinary IPC continues, and the private admission guard refuses reentry.
    startHold("TASK::69hold",.15,sender,&heldReply);sender.join();
    assert([heldReply containsString:@"c01_ipc_unavailable"]||[heldReply containsString:@"c01_request_expired"]);
    assert([take(invoke("TASK::61afterPrivateTimeout")) isEqualToString:@"0;;61afterPrivateTimeout\r\n"]);
    const char *payload="TASK::69reentrant";auto bounded=TLinkC01Encode((const uint8_t *)payload,strlen(payload),TLinkNativeDeadline(2));
    CFDataRef direct=CFDataCreate(NULL,bounded.data(),CFIndex(bounded.size()));
    assert([take(handleC01IPCMessage(NULL,TLinkC01IPCMessage,direct,NULL)) containsString:@"c01_ipc_busy"]);CFRelease(direct);
    std::this_thread::sleep_for(std::chrono::milliseconds(30));dispatch_semaphore_signal(released);
    assert(dispatch_semaphore_wait(exited,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert([take(invoke("TASK::69recovered",3)) isEqualToString:@"0;;69recovered\r\n"]);
    // Old/malformed transport and screenshot mutations are rejected before dispatch.
    const unsigned before=handlerCalls.load();
    const char *touch="TASK::10probe";std::vector<uint8_t> unbounded(touch,touch+strlen(touch));
    assert([rawPrivate(1,unbounded) containsString:@"c01_ipc_envelope_required"]);
    assert([rawPrivate(TLinkIPCNoReplyMessage,unbounded) containsString:@"c01_ipc_envelope_required"]);
    for(const char *unsupported:{"TASK::291;;legacy.png","TASK::292;;album.png","TASK::293","TASK::35extra"}){
        auto bytes=TLinkC01Encode((const uint8_t *)unsupported,strlen(unsupported),TLinkNativeDeadline(2));assert(!bytes.empty());
        assert([rawPrivate(TLinkC01IPCMessage,bytes) containsString:@"c01_ipc_task_not_allowed"]);
    }
    assert([rawPrivate(TLinkC01IPCMessage,unbounded) containsString:@"c01_ipc_envelope_invalid"]);
    auto expired=TLinkC01Encode((const uint8_t *)payload,strlen(payload),TLinkNativeNowNs()-1);
    assert([rawPrivate(TLinkC01IPCMessage,expired) containsString:@"c01_request_expired"]&&handlerCalls.load()==before);
    assert([take(invoke("TASK::69objcThrow",3)) containsString:@"request_failed"]);
    assert([take(invoke("TASK::69cppThrow",3)) containsString:@"request_failed"]);
    assert([take(invoke("TASK::69nested",3)) isEqualToString:@"0;;69nested\r\n"]);
    // Private requests do not depend on the legacy marker, and cannot fall back.
    assert(unlink(kTLinkautoIPCReadyMarkerPath)==0);
    assert([take(invoke("TASK::69withoutLegacyMarker",3)) isEqualToString:@"0;;69withoutLegacyMarker\r\n"]);
    assert([[@"ready" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[NSString stringWithUTF8String:kTLinkautoIPCReadyMarkerPath] atomically:NO]);
    isolated.stop();
    assert([take(invoke("TASK::69missingPort",1)) containsString:@"c01_ipc_unavailable"]);
    assert([take(invoke("TASK::61afterPrivateStop")) isEqualToString:@"0;;61afterPrivateStop\r\n"]);
    legacy.stop();assert(!invoke(kTLinkautoIPCCommandPing));
    puts("C01 IPC isolation passed: actual sender/owner queues, two real CF ports/run loops, deadline envelope gate, blocked-owner independence, late timeout/reentry, exceptions, source-failure cleanup and no legacy fallback. Device qualification pending.");
}}
