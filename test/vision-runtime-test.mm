#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>
#include <dispatch/dispatch.h>
#include <climits>
#include <new>
#include <cassert>
#include <cstdio>
#include <thread>
#include <string>
#include "../shared/TLinkNativeBudget.h"
static std::atomic<uint64_t> offset{0};
static std::shared_ptr<TLinkNativeCancellation> cancelDuringPerform;
static uint64_t FixtureNow(){return TLinkNativeNowNs()+offset.load();}
#include "VisionPolicyUnderTest.h"
#include "../shared/TLinkFrameVisionPolicy.h"
#include "VisionHeaderUnderTest.h"
#define SYSTEM_VERSION_LESS_THAN(value) false
#include "VisionUnderTest.inc"
// The production class/CI crop/request setup are real. Request execution and
// observations are controlled through KVC so lifecycle and fault paths are deterministic.
@interface FixtureBox:NSObject
@property CGPoint topLeft;
@property CGPoint topRight;
@property CGPoint bottomLeft;
@end
@implementation FixtureBox
@end
@interface FixtureText:NSObject
@property(copy) NSString *string;
@property(strong) FixtureBox *box;
- (id)boundingBoxForRange:(NSRange)range error:(NSError **)error;
@end
@implementation FixtureText
- (id)boundingBoxForRange:(NSRange)range error:(NSError **)error{return self.box;}
@end
@interface FixtureObservation:NSObject
@property(strong) NSArray *candidates;
- (NSArray *)topCandidates:(NSUInteger)count;
@end
@implementation FixtureObservation
- (NSArray *)topCandidates:(NSUInteger)count{return self.candidates;}
@end
@interface FixtureRequest:NSObject
@property(strong) NSArray *results;
@property float minimumTextHeight;
@property VNRequestTextRecognitionLevel recognitionLevel;
@property BOOL usesLanguageCorrection;
@property(copy) NSArray *customWords;
@property(copy) NSArray *recognitionLanguages;
@property(atomic) NSUInteger cancellations;
@property(strong) dispatch_semaphore_t cancelled;
- (void)cancel;
@end
@implementation FixtureRequest
- (void)cancel{self.cancellations=self.cancellations+1;dispatch_semaphore_signal(self.cancelled);}
@end
@interface FixtureHandler:NSObject
@property NSUInteger mode;
@property(strong) NSArray *output;
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error;
@end
@implementation FixtureHandler
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error {
    FixtureRequest *active=requests.firstObject;
    if(self.mode==1){if(error)*error=[NSError errorWithDomain:@"fixture" code:7 userInfo:nil];return false;}
    if(self.mode==2)@throw [NSException exceptionWithName:@"fixture" reason:@"perform fault" userInfo:nil];
    if(self.mode==3){offset.fetch_add(9000000000ULL);assert(dispatch_semaphore_wait(active.cancelled,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0);}
    if(self.mode==4){cancelDuringPerform->cancel();assert(dispatch_semaphore_wait(active.cancelled,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0);}
    if(self.mode==5)return false;
    active.results=self.output;return true;
}
@end
static CIImage *sourceImage(){return [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]] imageByCroppingToRect:CGRectMake(0,0,100,80)];}
static VKOcrManager *makeManager(){return [[VKOcrManager alloc] initWithCIImage:sourceImage() area:CGRectMake(10,20,50,40) orientation:1];}
static FixtureObservation *observation(NSString *string) {
    FixtureBox *box=[FixtureBox new];box.topLeft=CGPointMake(.25,.75);box.topRight=CGPointMake(.75,.75);box.bottomLeft=CGPointMake(.25,.25);
    FixtureText *text=[FixtureText new];text.string=string;text.box=box;
    FixtureObservation *value=[FixtureObservation new];value.candidates=@[text];return value;
}
static void inject(VKOcrManager *manager,FixtureHandler **handlerOut,FixtureRequest **requestOut){
    FixtureHandler *handler=[FixtureHandler new];handler.output=@[observation(@"hello")];
    FixtureRequest *request=[FixtureRequest new];request.cancelled=dispatch_semaphore_create(0);
    [manager setValue:handler forKey:@"requestHandler"];[manager setValue:request forKey:@"request"];
    *handlerOut=handler;*requestOut=request;
}
namespace cv {struct Mat {};}
#include "VisionFramePayload.inc"
static ZXFrameRef selectedFrame;
static TLinkImageComputeGate gImageCompute;
static TLinkImageMemory frameMemory(1024*1024,0,1024*1024);
static uint64_t zx_nowMs(){return FixtureNow()/1000000;}
static ZXFrameRef zx_snapshotFrame(uint32_t id){return id==1?selectedFrame:ZXFrameRef();}
static NSError *zx_frameError(NSString *message){return [NSError errorWithDomain:@"fixture.frame" code:999 userInfo:@{NSLocalizedDescriptionKey:message}];}
#include "VisionFrameProvider.inc"
static void selectFrame(){
    auto value=std::make_shared<ZXFrameObject>();value->width=100;value->height=80;value->bytesPerRow=400;value->scale=2;
    value->createdAtMs=zx_nowMs();value->expiresAtMs=value->createdAtMs+5000;value->hasBGRA=true;value->hasGray=false;
    value->charge=frameMemory.reserve(TLinkImageKind::Frame,32000);assert(value->charge);value->bgra.resize(32000,255);selectedFrame=value;
}
static bool dropFrameDuringInit=false;
static std::atomic<unsigned> captures{0},providers{0},orientationReads{0};
static bool expireCapture=false,failCapture=false;
@interface Screen:NSObject
+ (CGImageRef)createScreenShotCGImageRef;
+ (int)getScreenOrientation;
@end
@implementation Screen
+ (CGImageRef)createScreenShotCGImageRef {
    captures.fetch_add(1);
    if(expireCapture){expireCapture=false;offset.fetch_add(9000000000ULL);}
    if(failCapture){failCapture=false;return NULL;}
    void *data=calloc(100*80,4);assert(data);providers.fetch_add(1);
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,data,100*80*4,[](void *,const void *bytes,size_t){free((void *)bytes);providers.fetch_sub(1);});assert(provider);
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(100,80,8,32,400,rgb,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(rgb);CGDataProviderRelease(provider);assert(image);return image;
}
+ (int)getScreenOrientation{orientationReads.fetch_add(1);return 1;}
@end
@interface FixtureTaskManager:VKOcrManager
@end
@implementation FixtureTaskManager
- (id)initWithCGImage:(CGImageRef)image area:(CGRect)area orientation:(int)orientation {
    self=[super initWithCGImage:image area:area orientation:orientation];
    if(self){FixtureHandler *handler=nil;FixtureRequest *request=nil;inject(self,&handler,&request);if(dropFrameDuringInit){selectedFrame.reset();assert(frameMemory.stats().frames==32000);}}
    return self;
}
@end
static void showAlertBox(NSString *title,NSString *message,int code){}
#define TASK_TEXT_FROM_AREA 1
#define TASK_GET_SUPPORTED_LANGUAGE_LIST 2
#define TASK_TEXT_FROM_FRAME 6
#include "TextRecognizerUnderTest.inc"
int main(){@autoreleasepool{
    fputs("Vision Foundation: actual manager, CI crop, error/exception recovery and weak lifetime\n",stderr);
    @autoreleasepool{NSError *error=nil;assert(![[VKOcrManager new] recognize:&error]&&[error.localizedDescription containsString:@"vision_not_initialized"]);}
    @autoreleasepool{VKOcrManager *manager=[[VKOcrManager alloc] initWithCIImage:nil area:CGRectZero orientation:1];NSError *error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_roi_invalid_or_too_large"]);}
    __weak VKOcrManager *weakManager=nil;
    @autoreleasepool{VKOcrManager *manager=makeManager();weakManager=manager;}
    assert(!weakManager); // Detect the former request completion/self retain cycle.
    @autoreleasepool{
        VKOcrManager *manager=makeManager();FixtureHandler *handler=nil;FixtureRequest *request=nil;inject(manager,&handler,&request);
        NSError *error=nil;NSString *value=[manager recognize:&error];assert(!error&&[value isEqualToString:@"hello,,22,,30,,25,,20"]);
        FixtureObservation *empty=[FixtureObservation new];empty.candidates=@[];handler.output=@[empty,observation(@"hello")];
        value=[manager recognize:&error];assert(!error&&[value isEqualToString:@"hello,,22,,30,,25,,20"]);
        FixtureObservation *missingBox=observation(@"no box");((FixtureText *)missingBox.candidates.firstObject).box=nil;
        FixtureObservation *roundedBox=observation(@"rounded limit");
        FixtureBox *boundary=((FixtureText *)roundedBox.candidates.firstObject).box;
        boundary.topLeft=CGPointMake((static_cast<double>(INT_MAX/2)+1.0-10.0)/50.0,.75);
        boundary.topRight=CGPointMake(boundary.topLeft.x+.5,.75);
        handler.output=@[empty,missingBox,roundedBox,observation(@"hello")];error=nil;
        assert([[manager recognize:&error] isEqualToString:@"hello,,22,,30,,25,,20"]&&!error);
        handler.mode=5;error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_perform_failed"]);
        for(unsigned n=0;n<200;++n){
            handler.mode=n%2?1:2;error=nil;assert(![manager recognize:&error]&&error);
            assert(![[manager valueForKey:@"inProgress"] boolValue]);
            handler.mode=0;error=nil;assert([manager recognize:&error]&&!error);
        }
        [manager setValue:@1 forKey:@"inProgress"];error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_instance_busy"]);[manager setValue:@0 forKey:@"inProgress"];
        handler.output=@[];error=nil;assert([[manager recognize:&error] isEqualToString:@""]&&!error);
        NSMutableArray *many=[NSMutableArray array];for(unsigned n=0;n<4097;++n)[many addObject:empty];handler.output=many;
        error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_observation_limit"]);
        handler.output=@[observation([@"x" stringByPaddingToLength:1048577 withString:@"x" startingAtIndex:0])];
        error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_output_limit"]);
        (void)request;
    }
    @autoreleasepool{
        VKOcrManager *first=makeManager(),*second=makeManager(),*third=makeManager();NSError *error=nil;
        assert(![third recognize:&error]&&[error.localizedDescription containsString:@"vision_busy"]);(void)first;(void)second;
    }
    @autoreleasepool{
        VKOcrManager *manager=[[VKOcrManager alloc] initWithCIImage:sourceImage() area:CGRectMake(-1,0,10,10) orientation:1];
        NSError *error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_roi_invalid_or_too_large"]);
    }
    fputs("Vision Foundation: active local timeout invokes cancel, no late success or stuck inProgress\n",stderr);
    @autoreleasepool{
        VKOcrManager *manager=makeManager();FixtureHandler *handler=nil;FixtureRequest *request=nil;inject(manager,&handler,&request);
        handler.mode=3;NSError *error=nil;assert(![manager recognize:&error]&&[error.localizedDescription containsString:@"vision_cancelled_or_timed_out"]);
        assert(request.cancellations>0&&![[manager valueForKey:@"inProgress"] boolValue]);offset=0;
        handler.mode=0;error=nil;assert([manager recognize:&error]&&!error);
    }
    @autoreleasepool{
        auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,1048576);
        TLinkNativeBudgetScope parent(budget);VKOcrManager *manager=makeManager();
        FixtureHandler *handler=nil;FixtureRequest *request=nil;inject(manager,&handler,&request);
        cancelDuringPerform=token;handler.mode=4;NSError *error=nil;
        assert(![manager recognize:&error]&&request.cancellations>0&&[error.localizedDescription containsString:@"vision_cancelled_or_timed_out"]);
        cancelDuringPerform.reset();
    }
    fputs("Vision Foundation: production task parser/capture cleanup and pre-capture rejection\n",stderr);
    @autoreleasepool{
        NSError *error=nil;unsigned before=captures.load();
        const char *bad="1;;-1,,20,,50,,40;;;;0.03;;0;;;;0;;";
        assert(!performTextRecognizerTextFromRawData((UInt8 *)bad,&error)&&[error.localizedDescription containsString:@"vision_parameters_invalid"]&&captures==before);
        const char *good="1;;10,,20,,50,,40;;;;0.03;;0;;;;0;;";
        error=nil;assert([performTextRecognizerTextFromRawData((UInt8 *)good,&error) isEqualToString:@"hello,,22,,30,,25,,20"]&&!error);
        failCapture=true;error=nil;assert(!performTextRecognizerTextFromRawData((UInt8 *)good,&error)&&[error.localizedDescription containsString:@"capture_failed"]);
        expireCapture=true;error=nil;assert(!performTextRecognizerTextFromRawData((UInt8 *)good,&error)&&[error.localizedDescription containsString:@"vision_cancelled_or_timed_out"]);offset=0;
    }
    assert(providers==0);
    fputs("Vision Foundation: explicit frame selection, scaled ROI, no recapture/orientation lookup and held provider\n",stderr);
    @autoreleasepool{
        selectFrame();unsigned before=captures.load(),orientations=orientationReads.load();
        const char *frameRequest="6;;5,,10,,25,,20;;;;0.03;;0;;;;0;;;;1;;point;;5000";
        NSError *error=nil;assert([performTextRecognizerTextFromRawData((UInt8 *)frameRequest,&error) isEqualToString:@"hello,,22,,30,,25,,20"]&&!error);
        assert(captures==before&&orientationReads==orientations);
        dropFrameDuringInit=true;error=nil;assert([performTextRecognizerTextFromRawData((UInt8 *)frameRequest,&error) isEqualToString:@"hello,,22,,30,,25,,20"]&&!error);dropFrameDuringInit=false;
        assert(!selectedFrame&&captures==before&&orientationReads==orientations);
        error=nil;assert(!performTextRecognizerTextFromRawData((UInt8 *)frameRequest,&error)&&[error.localizedDescription containsString:@"vision_frame_not_found"]&&captures==before);
        const char *invalid="6;;0,,0,,0,,0;;;;0.03;;0;;;;0;;;;0;;pixel;;5000";
        error=nil;assert(!performTextRecognizerTextFromRawData((UInt8 *)invalid,&error)&&[error.localizedDescription containsString:@"vision_frame_parameters_invalid"]&&captures==before);
    }
    assert(frameMemory.stats().total==0);
    @autoreleasepool{
        selectFrame();auto expired=std::make_shared<ZXFrameObject>();expired->width=100;expired->height=80;expired->scale=2;expired->bytesPerRow=400;expired->hasBGRA=false;expired->hasGray=false;
        expired->createdAtMs=zx_nowMs()-2000;expired->expiresAtMs=zx_nowMs()+3000;selectedFrame=expired;
        unsigned before=captures.load();NSError *error=nil;
        const char *old="6;;0,,0,,0,,0;;;;0.03;;0;;;;0;;;;1;;pixel;;1000";
        assert(!performTextRecognizerTextFromRawData((UInt8 *)old,&error)&&[error.localizedDescription containsString:@"vision_frame_expired"]&&captures==before);selectedFrame.reset();
    }
    assert(frameMemory.stats().total==0);
    // Every fixture manager and timer callback has released its admission slot.
    {TLinkVisionContext a({}),b({}),c({});assert(a.admitted()&&b.admitted()&&!c.admitted());}
    puts("Vision Foundation passed: production init/crop/recognize, empty candidates, box coordinates, 200 error/exception recoveries, manager deallocation, observation/output caps, busy admission, active timeout cancellation and parent cancellation. UIKit debug drawing and real OCR execution remain device checks.");
}}
