#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import "../pccontrol/SocketServer.h"
#include "../shared/TLinkCaptureLeasePOSIX.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkIPCPolicy.h"
#include "../shared/TLinkNativeDispatch.h"
#include "../shared/TLinkTemplatePolicy.h"
#include "../tlinkauto-binary/IPCConstants.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
static NSData *encodedPNG;
static NSString *lastCapturePath,*lastRequestedPath;
static unsigned captureCalls=0,matchCalls=0;
static bool holdCapture=false,throwCapture=false,failMatch=false,throwMatch=false;
static dispatch_semaphore_t captureStarted,captureFinish,captureDone;
#include "OwnedWriter.inc"
// UIKit capture and OpenCV are controlled boundaries. PNG encoding/decoding,
// file ownership, daemon task orchestration, raw dispatch and CF callback are real.
@interface Screen:NSObject
+ (NSString *)screenShotToPath:(NSString *)path region:(CGRect)region error:(NSError **)error;
+ (void)saveToSystemAlbum:(NSString *)path error:(NSError **)error;
+ (void)clearSystemAlbum:(NSError **)error;
@end
@implementation Screen
+ (NSString *)screenShotToPath:(NSString *)path region:(CGRect)region error:(NSError **)error {
    (void)region;++captureCalls;lastCapturePath=[path copy];
    if(holdCapture){dispatch_semaphore_signal(captureStarted);assert(dispatch_semaphore_wait(captureFinish,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if(!zx_ownedCaptureContinue(error))return nil;
    if(throwCapture)@throw [NSException exceptionWithName:@"CaptureFixture" reason:@"capture failure" userInfo:nil];
    return zx_writeOwnedCapture(path,encodedPNG,error)?path:nil;
}
+ (void)saveToSystemAlbum:(NSString *)path error:(NSError **)error {(void)path;(void)error;assert(false);}
+ (void)clearSystemAlbum:(NSError **)error {(void)error;assert(false);}
@end
#include "OwnedScreenshotConstants.h"
#include "OwnedScreenshotHandler.inc"
static void processTaskWithContext(UInt8 *bytes,size_t length,CFWriteStreamRef stream,id context){
    (void)context;assert(length>=2&&bytes[0]=='2'&&bytes[1]=='9');
    NSError *error=nil;NSString *path=handleScreenshotTaskFromRawData(bytes+2,&error);
    NSString *reply=error?error.localizedDescription:[NSString stringWithFormat:@"0;;%@\r\n",path?:@""];
    notifyClient((UInt8 *)reply.UTF8String,stream);
}
static void sendHardwareKeyEventFromRawData(UInt8 *,NSError **) {assert(false);}
#include "OwnedIPCHandler.inc"
#include "OwnedIPCQueues.inc"
static dispatch_queue_t springboardQueue(){static dispatch_queue_t queue=dispatch_queue_create("test.owned.capture.springboard",DISPATCH_QUEUE_SERIAL);return queue;}
static bool lateReply=false,foreignReply=false;
static CFDataRef sendIPCMessage(const char *payload,bool wait){
    assert(wait);lastRequestedPath=[NSString stringWithUTF8String:payload+11];auto budget=TLinkCurrentNativeBudget();assert(budget&&budget->deadline());
    const auto envelope=TLinkC01Encode((const uint8_t *)payload,strlen(payload),budget->deadline());assert(!envelope.empty());
    NSData *wire=[NSData dataWithBytes:envelope.data() length:envelope.size()];
    if(foreignReply){const char *reply="0;;/tmp/foreign-owned-capture.png\r\n";return CFDataCreate(NULL,(const UInt8 *)reply,strlen(reply));}
    if(lateReply){
        dispatch_async(springboardQueue(),^{@autoreleasepool{
            CFDataRef reply=handleIPCMessage(NULL,TLinkC01IPCMessage,(__bridge CFDataRef)wire,NULL);if(reply)CFRelease(reply);
            dispatch_semaphore_signal(captureDone);
        }});
        assert(dispatch_semaphore_wait(captureStarted,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        return NULL; // Model transport timeout while the opaque capture is still running.
    }
    __block CFDataRef response=NULL;
    dispatch_sync(springboardQueue(),^{response=handleIPCMessage(NULL,TLinkC01IPCMessage,(__bridge CFDataRef)wire,NULL);});return response;
}
static void zx_logf(const char *,...) {}
#include "OwnedDaemonHelper.inc"
#include "OwnedDaemonPath.inc"
@interface TemplateMatch:NSObject
- (void)setAcceptableValue:(float)value;
- (void)setMaxTryTimes:(int)value;
- (void)setScaleRation:(float)value;
- (CGRect)templateMatchWithPath:(NSString *)path templatePath:(NSString *)templatePath error:(NSError **)error;
@end
@implementation TemplateMatch
- (void)setAcceptableValue:(float)value {assert(value>=0&&value<=1);}
- (void)setMaxTryTimes:(int)value {assert(value>=0&&value<=8);}
- (void)setScaleRation:(float)value {assert(value>=.1f&&value<=1.9f);}
- (CGRect)templateMatchWithPath:(NSString *)path templatePath:(NSString *)templatePath error:(NSError **)error {
    (void)templatePath;++matchCalls;
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);assert(source);
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);assert(image&&CGImageGetWidth(image)==4&&CGImageGetHeight(image)==4);
    CGImageRelease(image);CFRelease(source);
    if(throwMatch)throw std::runtime_error("controlled matcher exception");
    if(failMatch){if(error)*error=[NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"-1;;match_failed\r\n"}];return CGRectZero;}
    return CGRectMake(1,2,3,4);
}
@end
static void scheduleCaptureLeaseCleanup(){} // Controlled scheduling boundary; the POSIX sweep has its own isolated-directory harness.
#include "OwnedDaemonTask.inc"
static void makePNG(){
    uint8_t pixels[64];memset(pixels,255,sizeof(pixels));
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();assert(space);
    CGContextRef context=CGBitmapContextCreate(pixels,4,4,8,16,space,kCGImageAlphaPremultipliedLast);assert(context);
    CGImageRef image=CGBitmapContextCreateImage(context);assert(image);
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.png"),1,NULL);assert(destination);
    CGImageDestinationAddImage(destination,image,NULL);assert(CGImageDestinationFinalize(destination));
    CFRelease(destination);CGImageRelease(image);CGContextRelease(context);CGColorSpaceRelease(space);encodedPNG=[data copy];
}
static bool exists(const std::string &path){struct stat st;return lstat(path.c_str(),&st)==0;}
static void gone(NSString *path){assert(path&& !exists(path.UTF8String)&& !exists(std::string(path.UTF8String)+".lease")&& !exists(std::string(path.UTF8String)+".lease.owner.v1"));}
static NSString *invoke(NSString *templatePath){
    auto budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(3),1024);
    TLinkNativeBudgetScope scope(budget);
    NSString *wire=[@"21" stringByAppendingString:templatePath];char *reply=handleTemplateMatchTaskInDaemon(wire.UTF8String);assert(reply);
    NSString *value=[NSString stringWithUTF8String:reply];free(reply);return value;
}
static void posixCases(){
    const std::string output=zx_makeTempScreenshotPath().UTF8String,marker=output+".lease";
    {TLinkCaptureClientLease client(output);assert(client.valid());TLinkCaptureReceiverLease receiver(output,{});assert(receiver.valid());
        assert(receiver.write(encodedPNG.bytes,encodedPNG.length));assert(exists(output));client.cancel();receiver.finish();}assert(!exists(output)&&!exists(marker));
    // A foreign existing file is never overwritten or removed by failed admission.
    assert([encodedPNG writeToFile:[NSString stringWithUTF8String:output.c_str()] atomically:NO]);
    {TLinkCaptureClientLease client(output);assert(!client.valid());}assert(exists(output));assert(unlink(output.c_str())==0);
    // Symlink and hard-linked markers cannot authorize an output write.
    const std::string target=output+".target";assert([encodedPNG writeToFile:[NSString stringWithUTF8String:target.c_str()] atomically:NO]);
    assert(symlink(target.c_str(),marker.c_str())==0);
    {TLinkCaptureReceiverLease receiver(output,{});assert(!receiver.valid()&&!receiver.write(encodedPNG.bytes,encodedPNG.length));}
    assert(unlink(marker.c_str())==0&&exists(target));assert(unlink(target.c_str())==0);
    {TLinkCaptureClientLease client(output);assert(client.valid());assert(link(marker.c_str(),target.c_str())==0);
        TLinkCaptureReceiverLease receiver(output,{});assert(!receiver.valid());assert(unlink(target.c_str())==0);}
    assert(!exists(marker));
    // Replacement output identity survives receiver cleanup; unlink never descends into directories.
    {TLinkCaptureClientLease client(output);TLinkCaptureReceiverLease receiver(output,{});assert(receiver.write(encodedPNG.bytes,encodedPNG.length));
        client.cancel();assert(mkdir(output.c_str(),0700)==0);receiver.finish();assert(exists(output));assert(rmdir(output.c_str())==0);assert(unlink((marker+".owner.v1").c_str())==0);}
    {TLinkCaptureClientLease client(output);assert(client.valid());assert(mkdir(output.c_str(),0700)==0);client.cancel();assert(exists(output));assert(rmdir(output.c_str())==0);assert(unlink((marker+".owner.v1").c_str())==0);}
    assert(!exists(output)&&!exists(marker));
    std::vector<uint8_t> bytes(256*1024,71);
    for(unsigned n=0;n<64;++n){
        TLinkCaptureClientLease client(output);assert(client.valid());
        auto ready=dispatch_semaphore_create(0);
        std::thread writer([&]{TLinkCaptureReceiverLease receiver(output,{});
            dispatch_semaphore_signal(ready);receiver.write(bytes.data(),bytes.size());receiver.finish();});
        assert(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        client.cancel();writer.join();assert(!exists(output)&&!exists(marker));
    }
}
int main(){@autoreleasepool{
    (void)kTLinkautoIPCPortName;(void)kTLinkautoC01IPCPortName;(void)kTLinkautoIPCReadyMarkerPath;makePNG();posixCases();
    NSString *templatePath=[zx_makeTempScreenshotPath() stringByAppendingString:@".fixture"];assert([encodedPNG writeToFile:templatePath atomically:NO]);
    assert([invoke(templatePath) isEqualToString:@"0;;1.00;;2.00;;3.00;;4.00\r\n"]);gone(lastCapturePath);assert(matchCalls==1);
    failMatch=true;assert([invoke(templatePath) containsString:@"match_failed"]);gone(lastCapturePath);failMatch=false;
    throwMatch=true;bool caught=false;try{invoke(templatePath);}catch(const std::runtime_error &){caught=true;}assert(caught);gone(lastCapturePath);throwMatch=false;
    // Exceptions cannot be thrown across libdispatch/CF transport boundaries.
    // Exercise receiver unwinding directly on its owner thread instead.
    throwCapture=true;caught=false;
    NSString *exceptionPath=zx_makeTempScreenshotPath();
    {TLinkCaptureClientLease client(exceptionPath.UTF8String);assert(client.valid());
        NSString *payload=[@"TASK::294;;" stringByAppendingString:exceptionPath];
        auto wire=TLinkC01Encode((const uint8_t *)payload.UTF8String,strlen(payload.UTF8String),TLinkNativeDeadline(3));
        NSData *data=[NSData dataWithBytes:wire.data() length:wire.size()];
        @try{CFDataRef reply=handleIPCMessage(NULL,TLinkC01IPCMessage,(__bridge CFDataRef)data,NULL);if(reply)CFRelease(reply);}
        @catch(NSException *error){(void)error;caught=true;}
        assert(caught&&TLinkCaptureReceiverSlot()==nullptr);client.cancel();
    }gone(exceptionPath);throwCapture=false;
    foreignReply=true;assert([invoke(templatePath) containsString:@"reply_path_mismatch"]);gone(lastRequestedPath);foreignReply=false;
    // No scoped private lease: reject before touching the controlled capture boundary.
    const unsigned before=captureCalls;NSError *error=nil;
    NSString *raw=[@"4;;" stringByAppendingString:zx_makeTempScreenshotPath()];assert(!handleScreenshotTaskFromRawData((UInt8 *)raw.UTF8String,&error));assert(error&&captureCalls==before);
    // Actual daemon returns on transport failure, cancels its marker, then the actual
    // CF callback resumes and refuses to publish the PNG prepared by a late capture.
    captureStarted=dispatch_semaphore_create(0);captureFinish=dispatch_semaphore_create(0);captureDone=dispatch_semaphore_create(0);
    holdCapture=lateReply=true;const unsigned matchesBefore=matchCalls;
    assert([invoke(templatePath) containsString:@"no_response"]);assert(!exists(lastCapturePath.UTF8String)&&!exists(std::string(lastCapturePath.UTF8String)+".lease"));
    assert(exists(std::string(lastCapturePath.UTF8String)+".lease.owner.v1"));
    dispatch_semaphore_signal(captureFinish);assert(dispatch_semaphore_wait(captureDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    gone(lastCapturePath);assert(matchCalls==matchesBefore);holdCapture=lateReply=false;
    dispatch_sync(springboardQueue(),^{});assert(unlink(templatePath.fileSystemRepresentation)==0);encodedPNG=nil;lastCapturePath=nil;lastRequestedPath=nil;
    puts("Owned capture Foundation passed: actual daemon/CF callback/raw handler/write adapter, real PNG/POSIX leases, late transport return, matcher/capture failures, exceptions, private admission and nonrecursive ownership cleanup. UIKit capture/OpenCV/device qualification pending.");
}}
