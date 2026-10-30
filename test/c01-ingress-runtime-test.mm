#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../pccontrol/TLinkTaskContext.h"
#import "../pccontrol/SocketServer.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkVPNIPC.h"
#include "../shared/TLinkIPCPolicy.h"
#include "../tlinkauto-binary/IPCConstants.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <unistd.h>
static unsigned licenseCalls=0,handlerCalls=0;
static bool denyLicense=false,slowLicense=false;
static uint64_t observedDeadline=0;
enum {TASK_PERFORM_TOUCH=10,TASK_USLEEP=18,TASK_HARDWARE_KEY=30,TASK_IMAGE_OBJECT=48,TASK_FRAME_RELEASE=67};
static std::atomic<uint64_t> sTLinkSpringBoardLicenseTask10DropCount{0};
static int getTaskType(UInt8 *bytes){return int(bytes[0]-'0')*10+bytes[1]-'0';}
static BOOL TLinkRootfullLicenseTaskAllowed(int,NSString **denial){
    ++licenseCalls;if(slowLicense)std::this_thread::sleep_for(std::chrono::milliseconds(20));
    if(denyLicense){if(denial)*denial=@"-1;;fixture_license_denied\r\n";return false;}return true;
}
#include "C01TaskEntry.inc"
    ++handlerCalls;observedDeadline=TLinkCurrentNativeBudget()->deadline();
    notifyClient((UInt8 *)"0;;handled\r\n",writeStreamRef);
}
static TLinkTaskExecutionContext *context(double timeout=30,bool cleanup=false){
    auto result=[TLinkTaskExecutionContext new];result.cancellationToken=[TLinkCancellationToken new];
    [result setNativeBudget:std::make_shared<TLinkNativeBudget>([result.cancellationToken nativeCancellation],TLinkNativeDeadline(timeout),128,cleanup,true)];
    return result;
}
static NSString *invoke(const char *wire,TLinkTaskExecutionContext *ctx){
    uint8_t placeholder[1]={0};CFWriteStreamRef stream=CFWriteStreamCreateWithBuffer(NULL,placeholder,1);assert(stream&&CFWriteStreamOpen(stream));
    processTaskWithContext((UInt8 *)wire,strlen(wire),stream,ctx);CFWriteStreamClose(stream);CFRelease(stream);
    const auto &bytes=[ctx nativeBudget]->response();return [[NSString alloc] initWithBytes:bytes.data() length:bytes.size() encoding:NSUTF8StringEncoding];
}
static unsigned sends=0,taskSends=0;static SInt32 lastMessage=0;static double lastSend=0,lastReceive=0;
static std::vector<uint8_t> lastBytes;
static bool portValid=true,denyRemote=false,unknownEnvelope=false,missingMarker=false,denyPrivate=false;
static CFStringRef lastPortName=NULL;static unsigned markerChecks=0;
static int FixtureAccess(const char *,int){++markerChecks;return missingMarker?-1:0;}
static CFDataRef FixturePortCallback(CFMessagePortRef,SInt32,CFDataRef,void *){return NULL;}
static CFMessagePortRef FixtureRemote(CFAllocatorRef,CFStringRef name){
    lastPortName=name;
    if(denyRemote||(denyPrivate&&CFEqual(name,kTLinkautoC01IPCPortName)))return NULL;
    CFMessagePortContext portContext={0,NULL,NULL,NULL,NULL};Boolean shouldFree=false;
    NSString *fixtureName=[@"test.c01.ingress." stringByAppendingString:NSUUID.UUID.UUIDString];
    return CFMessagePortCreateLocal(kCFAllocatorDefault,(__bridge CFStringRef)fixtureName,FixturePortCallback,&portContext,&shouldFree);
}
static Boolean FixtureValid(CFMessagePortRef port){if(!portValid){CFMessagePortInvalidate(port);return false;}return CFMessagePortIsValid(port);}
static SInt32 FixtureSend(CFMessagePortRef,SInt32 message,CFDataRef data,CFTimeInterval send,CFTimeInterval receive,CFStringRef,CFDataRef *response){
    ++sends;if(CFDataGetLength(data)!=8||memcmp(CFDataGetBytePtr(data),"CMD_PING",8)!=0)++taskSends;lastMessage=message;lastSend=send;lastReceive=receive;
    lastBytes.assign(CFDataGetBytePtr(data),CFDataGetBytePtr(data)+CFDataGetLength(data));
    const char *reply=unknownEnvelope&&message==TLinkC01IPCMessage?"1;;unknown_command\r\n":"0;;fixture\r\n";
    if(response)*response=CFDataCreate(NULL,(const UInt8 *)reply,strlen(reply));return kCFMessagePortSuccess;
}
static bool zx_isHotPathPayload(const char *){return true;}
#include "VPNIPCSender.inc"
#include "C01IPCSender.inc"
static NSString *ownedReply(CFDataRef value){assert(value);NSData *data=CFBridgingRelease(value);return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
int main(){@autoreleasepool{
    (void)kTLinkautoIPCReadyMarkerPath;(void)kTLinkautoIPCCommandHome;(void)kTLinkautoIPCCommandTaskPrefix;
    auto ctx=context();const uint64_t original=[ctx nativeBudget]->deadline();
    const uint64_t start=TLinkNativeNowNs();assert([invoke("69fixture",ctx) isEqualToString:@"0;;handled\r\n"]);
    assert(handlerCalls==1&&licenseCalls==1&&observedDeadline>=start&&observedDeadline<=TLinkNativeNowNs()+3000000000ULL&&[ctx nativeBudget]->deadline()==original);
    denyLicense=true;assert([invoke("69fixture",context()) containsString:@"fixture_license_denied"]&&handlerCalls==1);denyLicense=false;
    slowLicense=true;assert([invoke("69fixture",context(.005)) containsString:@"native_cancelled_or_timed_out"]&&handlerCalls==1);slowLicense=false;
    ctx=context();[ctx.cancellationToken cancel];unsigned before=licenseCalls;
    assert([invoke("69fixture",ctx) containsString:@"native_cancelled_or_timed_out"]&&licenseCalls==before&&handlerCalls==1);
    ctx=context(0,true);[ctx.cancellationToken cancel];assert([invoke("67fixture",ctx) isEqualToString:@"0;;handled\r\n"]&&licenseCalls==before&&handlerCalls==2);
    auto parent=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(3),128);
    {
        TLinkNativeBudgetScope scope(parent);assert([ownedReply(sendIPCMessage("TASK::69fixture",true)) hasPrefix:@"0;;"]);
        assert(CFEqual(lastPortName,kTLinkautoC01IPCPortName)&&markerChecks==0);
        assert(lastMessage==TLinkC01IPCMessage&&lastSend>0&&lastReceive>0&&lastSend+lastReceive<=3);
        TLinkC01Envelope envelope;assert(TLinkC01Decode(lastBytes.data(),lastBytes.size(),envelope)==TLinkC01DecodeResult::Valid&&envelope.deadline==parent->deadline());
        assert([ownedReply(sendIPCMessage("TASK::291;;/tmp/fixture.png",true)) hasPrefix:@"0;;"]&&lastMessage==TLinkC01IPCMessage);
        unknownEnvelope=true;before=taskSends;assert([ownedReply(sendIPCMessage("TASK::69fixture",true)) containsString:@"unknown_command"]&&taskSends==before+1);unknownEnvelope=false;
    }
    assert([ownedReply(sendIPCMessage("TASK::61fixture",true)) hasPrefix:@"0;;"]&&lastMessage==1&&lastSend==5&&lastReceive==5);
    assert(!sendIPCMessage("TASK::10fixture",false)&&lastMessage==2&&lastSend==1.5);
    parent=std::make_shared<TLinkNativeBudget>(TLinkNativeNowNs()-1,TLinkNativeBudgetPtr{});
    {TLinkNativeBudgetScope scope(parent);before=sends;assert([ownedReply(sendIPCMessage("TASK::69fixture",true)) containsString:@"c01_request_expired"]&&sends==before);}
    missingMarker=true;
    {TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(TLinkNativeDeadline(3),TLinkNativeBudgetPtr{}));assert([ownedReply(sendIPCMessage("TASK::69fixture",true)) hasPrefix:@"0;;"]);}
    assert(!sendIPCMessage(kTLinkautoIPCCommandPing,true));missingMarker=false;
    portValid=false;denyPrivate=true;
    {TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(TLinkNativeDeadline(3),TLinkNativeBudgetPtr{}));
        before=taskSends;assert([ownedReply(sendIPCMessage("TASK::69fixture",true)) containsString:@"c01_ipc_unavailable"]&&taskSends==before&&CFEqual(lastPortName,kTLinkautoC01IPCPortName));}
    portValid=true;assert([ownedReply(sendIPCMessage("TASK::61fixture",true)) hasPrefix:@"0;;"]);
    portValid=false;denyRemote=true;assert(!sendIPCMessage(kTLinkautoIPCCommandPing,true));
    puts("C01 Foundation passed: actual root task-entry before/after license, parent sink/deadline preservation, cleanup exemption, actual IPC envelope/timeouts and no legacy retry.");
}}
