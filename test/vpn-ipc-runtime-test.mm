#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import "../pccontrol/SocketServer.h"
#include "../shared/TLinkVPNIPC.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkIPCPolicy.h"
#include "../shared/TLinkCaptureLeasePOSIX.h"
#include "../shared/TLinkNativeDispatch.h"
#include "VPNIPCConstants.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <string>
static const char *fixturePortName=nullptr;
static dispatch_semaphore_t entered,released,exited;
static std::atomic<unsigned> vpnCalls{0},legacyCalls{0},imageCalls{0};
static CFDataRef handleVPNIPCMessage(CFMessagePortRef,SInt32,CFDataRef,void *);
static NSString *take(CFDataRef reply){assert(reply);NSData *data=CFBridgingRelease(reply);return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
static void processTaskWithContext(UInt8 *bytes,size_t length,CFWriteStreamRef stream,id context){
    (void)context;NSString *wire=[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];assert(wire);
    if([wire hasPrefix:@"59"]){++vpnCalls;auto budget=TLinkCurrentNativeBudget();assert(budget&&budget->deadline());}
    else if([wire hasPrefix:@"69"])++imageCalls;else ++legacyCalls;
    if([wire hasSuffix:@"hold"]){dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(released,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if([wire isEqualToString:@"59objcThrow"])@throw [NSException exceptionWithName:@"Fixture" reason:@"controlled" userInfo:nil];
    if([wire isEqualToString:@"59cppThrow"])throw std::runtime_error("controlled");
    if([wire isEqualToString:@"59nested"]){
        const char *payload="TASK::590";auto bytes=TLinkVPNIPCEncode((const uint8_t *)payload,strlen(payload),TLinkNativeDeadline(2));
        CFDataRef data=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size()));
        assert([take(handleVPNIPCMessage(NULL,TLinkVPNIPCMessage,data,NULL)) containsString:@"vpn_ipc_busy"]);CFRelease(data);
    }
    NSString *reply=[NSString stringWithFormat:@"0;;%@\r\n",wire];notifyClient((UInt8 *)reply.UTF8String,stream);
    if([wire hasSuffix:@"hold"])dispatch_semaphore_signal(exited);
}
static void sendHardwareKeyEventFromRawData(UInt8 *,NSError **){assert(false);}
#include "VPNIPCHandler.inc"
#include "C01IPCReceiver.inc"
static bool failSource=false;
static CFRunLoopSourceRef FixtureSource(CFAllocatorRef allocator,CFMessagePortRef port,CFIndex order){return failSource?NULL:CFMessagePortCreateRunLoopSource(allocator,port,order);}
#define CFMessagePortCreateRunLoopSource FixtureSource
#include "VPNIPCReceiver.inc"
#undef CFMessagePortCreateRunLoopSource
#include "VPNIPCSender.inc"
#include "C01IPCQueues.inc"
static bool zx_isHotPathPayload(const char *){return true;}
#include "C01IPCSender.inc"
class Server {
    std::thread thread_;CFRunLoopRef loop_=NULL;
public:
    Server(CFStringRef name,unsigned kind){
        auto ready=dispatch_semaphore_create(0);
        thread_=std::thread([this,name,kind,ready]{@autoreleasepool{
            CFMessagePortRef port=NULL;CFRunLoopSourceRef source=NULL;
            if(kind==2)assert(zx_installVPNIPCSource(name,&port,&source));
            else if(kind==1)assert(zx_installC01IPCSource(name,&port,&source));
            else{CFMessagePortContext context={0,NULL,NULL,NULL,NULL};Boolean shouldFree=false;
                port=CFMessagePortCreateLocal(NULL,name,handleIPCMessage,&context,&shouldFree);assert(port);
                source=CFMessagePortCreateRunLoopSource(NULL,port,0);assert(source);CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopCommonModes);
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
static CFDataRef invoke(const char *payload,double seconds=2){
    auto budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(seconds),1024);
    TLinkNativeBudgetScope scope(budget);__block CFDataRef reply=NULL;
    TLinkNativeDispatchSync(zx_ipcRequestQueue(payload,true), ^{reply=sendIPCMessage(payload,true);});return reply;
}
static void protocolCases(){
    const unsigned before=vpnCalls.load();
    assert([take(handleVPNIPCMessage(NULL,1,NULL,NULL)) containsString:@"vpn_ipc_envelope_required"]);
    const char *raw="TASK::590";CFDataRef data=CFDataCreate(NULL,(const UInt8 *)raw,strlen(raw));
    assert([take(handleVPNIPCMessage(NULL,TLinkVPNIPCMessage,data,NULL)) containsString:@"vpn_ipc_invalid"]);CFRelease(data);
    auto bytes=TLinkVPNIPCEncode((const uint8_t *)raw,strlen(raw),TLinkNativeNowNs()-1);
    data=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size()));assert([take(handleVPNIPCMessage(NULL,TLinkVPNIPCMessage,data,NULL)) containsString:@"vpn_ipc_expired"]);CFRelease(data);
    bytes=TLinkVPNIPCEncode((const uint8_t *)raw,strlen(raw),TLinkNativeDeadline(2));bytes[19]='8';
    data=CFDataCreate(NULL,bytes.data(),CFIndex(bytes.size()));assert([take(handleVPNIPCMessage(NULL,TLinkVPNIPCMessage,data,NULL)) containsString:@"vpn_ipc_invalid"]);CFRelease(data);
    assert(vpnCalls.load()==before);
    failSource=true;CFMessagePortRef port=NULL;CFRunLoopSourceRef source=NULL;
    assert(!zx_installVPNIPCSource(CFSTR("test.vpn.ipc.source.failure"),&port,&source)&&!port&&!source);failSource=false;
}
static void isolationCases(){
    assert(zx_ipcRequestQueue("TASK::590",true)==zx_vpnIPCQueue());
    assert(zx_ipcRequestQueue("TASK::590",false)==ipcQueue());
    assert(zx_ipcRequestQueue("TASK::580",true)==ipcQueue());
    const std::string oversized="TASK::59"+std::string(4088,'x');const unsigned oversizedBefore=vpnCalls.load();
    assert(zx_ipcRequestQueue(oversized.c_str(),true)==zx_vpnIPCQueue());
    assert([take(invoke(oversized.c_str())) containsString:@"vpn_ipc_invalid"]&&vpnCalls.load()==oversizedBefore);
    assert([take(invoke("TASK::590")) isEqualToString:@"0;;590\r\n"]);
    for(const char *wire:{"TASK::59objcThrow","TASK::59cppThrow"})assert([take(invoke(wire)) containsString:@"request_failed"]);
    assert([take(invoke("TASK::59nested")) isEqualToString:@"0;;59nested\r\n"]);
    auto done=dispatch_semaphore_create(0);
    dispatch_async(zx_vpnIPCQueue(), ^{@autoreleasepool{
        auto budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(2),1024);TLinkNativeBudgetScope scope(budget);
        assert([take(sendIPCMessage("TASK::59hold",true)) isEqualToString:@"0;;59hold\r\n"]);dispatch_semaphore_signal(done);
    }});
    assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    // Actual independent legacy and image queues/ports remain usable while VPN waits.
    assert([take(invoke("CMD_PING")) hasPrefix:@"0"]);
    assert([take(invoke("TASK::69warm")) isEqualToString:@"0;;69warm\r\n"]);
    assert([take(invoke("TASK::61warm")) isEqualToString:@"0;;61warm\r\n"]);
    dispatch_semaphore_signal(released);assert(dispatch_semaphore_wait(exited,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    // Timeout is not replayed on legacy IPC; the original handler may finish late.
    done=dispatch_semaphore_create(0);const unsigned oldLegacy=legacyCalls.load();
    dispatch_async(zx_vpnIPCQueue(), ^{@autoreleasepool{
        auto budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(.5),1024);TLinkNativeBudgetScope scope(budget);
        NSString *reply=take(sendIPCMessage("TASK::59hold",true));assert([reply containsString:@"vpn_ipc_expired"]||[reply containsString:@"vpn_ipc_unavailable"]);dispatch_semaphore_signal(done);
    }});
    assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(legacyCalls.load()==oldLegacy);assert([take(invoke("CMD_PING")) hasPrefix:@"0"]);
    dispatch_semaphore_signal(released);assert(dispatch_semaphore_wait(exited,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert([take(invoke("TASK::590")) hasPrefix:@"0;;"]);
    auto token=std::make_shared<TLinkNativeCancellation>();token->cancel();const unsigned before=vpnCalls.load();
    dispatch_sync(zx_vpnIPCQueue(), ^{TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(token,0,1024));assert([take(sendIPCMessage("TASK::590",true)) containsString:@"vpn_ipc_expired"]);});
    assert(vpnCalls.load()==before);
}
int main(){@autoreleasepool{
    puts("VPN IPC Foundation: actual sender/queue/envelope/handler and three real CF ports/run loops");
    entered=dispatch_semaphore_create(0);released=dispatch_semaphore_create(0);exited=dispatch_semaphore_create(0);
    const std::string name="test.vpn."+std::string(NSUUID.UUID.UUIDString.UTF8String);fixturePortName=name.c_str();
    CFStringRef portName=CFStringCreateWithCString(NULL,fixturePortName,kCFStringEncodingUTF8);assert(portName);
    protocolCases();Server legacy(kTLinkautoIPCPortName,0),image(kTLinkautoC01IPCPortName,1),vpn(portName,2);
    isolationCases();vpn.stop();const unsigned before=legacyCalls.load();
    NSString *missing=take(invoke("TASK::590"));assert([missing containsString:@"vpn_ipc_unavailable"]||[missing containsString:@"vpn_ipc_expired"]);assert(legacyCalls.load()==before);
    assert([take(invoke("CMD_PING")) hasPrefix:@"0"]);image.stop();legacy.stop();CFRelease(portName);
    puts("VPN IPC Foundation passed: task/deadline gates, source cleanup, NS/C++/nested unwind, held-VPN legacy/image independence, timeout/late recovery, cancelled caller and missing-port refusal without fallback. Daemon task-lane isolation/device qualification pending.");
}return 0;}
