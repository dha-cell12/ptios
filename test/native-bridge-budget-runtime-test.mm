#include "../shared/TLinkNativeTouchRequest.h"
#include "../shared/TLinkNativeColorRequest.h"
#include "../shared/TLinkNativeColorRange.h"
#include "../shared/TLinkNativeColorPoints.h"
#include "../shared/TLinkNativeColorMulti.h"
#include "../shared/TLinkNativeFramePick.h"
#include "../shared/TLinkNativeFrameImage.h"
#include "../shared/TLinkNativeFrameRelease.h"
#include "../shared/TLinkNativeFrameCapture.h"
#include "../shared/TLinkNativeFrameCaptureResult.h"
#include "../shared/TLinkNativeImageRelease.h"
#include "../shared/TLinkNativeImageOpen.h"
#include "../shared/TLinkNativeImageCapture.h"
#include "../shared/TLinkNativeImageResult.h"
#import "../pccontrol/TesseractOCRTask.h"
#include "../shared/TLinkNativeOCRInput.h"
#include "../shared/TLinkNativeFrameSearch.h"
#include "../shared/TLinkNativeFrameColors.h"
#include "../shared/TLinkNativeFrameMulti.h"
#include "../shared/TLinkModernImagePolicy.h"
#include "../shared/TLinkColorPolicy.h"
#include "../shared/TLinkC01Ingress.h"
// Actual bridge, context, response writer and gestures; hardware/task/UI doubles only.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../pccontrol/TLinkTaskContext.h"
#import "../pccontrol/DeviceInfo.h"
#import "../pccontrol/Connectivity.h"
#import "../pccontrol/SocketServer.h"
#import "../pccontrol/jsruntime/TLinkJSNativeRequest.h"
#import "../pccontrol/jsruntime/TLinkJSNativeResponse.h"
#include "../shared/TLinkNativeDispatch.h"
#include "../shared/TLinkRawPlayback.h"
#include <cassert>
#include <climits>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <stdexcept>
#include <vector>
#include <set>
NSDictionary *TLinkExecuteNativeImageOpen(const TLinkNativeImageOpenRequest &,TLinkTaskExecutionContext *);
static void imageOpenLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static void imageOpenRollbackLegacyTask(UInt8 *,CFWriteStreamRef);
static unsigned trackImages=0;static int lastTrackedImage=-1;
NSDictionary *TLinkExecuteNativeImageCapture(const TLinkNativeImageCaptureRequest &,TLinkTaskExecutionContext *);
static void imageCaptureLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static void imageCaptureRollbackLegacyTask(UInt8 *,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrontmost(int,TLinkTaskExecutionContext *);
static void frontmostLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_FRONTMOST_APP_ID=34,TASK_FRONTMOST_APP_ORIENTATION=35};
NSDictionary *TLinkExecuteNativePath(int,TLinkTaskExecutionContext *);
static void pathLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_ROOT_DIR=44,TASK_CURRENT_DIR=45,TASK_BOT_PATH=46};
NSDictionary *TLinkExecuteNativeHardwareKey(int,int,TLinkTaskExecutionContext *);
static void hardwareKeyLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_HARDWARE_KEY=30};
NSDictionary *TLinkExecuteNativeKeepAwake(BOOL,TLinkTaskExecutionContext *);
static void keepAwakeLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_KEEP_AWAKE=40};
NSDictionary *TLinkExecuteNativeIndicator(int,TLinkTaskExecutionContext *);
static void indicatorLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_TOUCH_INDICATOR=26};
NSDictionary *TLinkExecuteNativeFrontmostPid(TLinkTaskExecutionContext *);
static void frontmostPidLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_FRONTMOST_PID=51};
NSDictionary *TLinkExecuteNativeAppPid(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeAppState(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeAppInfo(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeAppPaths(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeKillApp(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeOpenApp(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeListBundles(BOOL,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeOpenUrl(NSString *,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeDeviceInfo(int,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeOCRLanguages(TLinkTaskExecutionContext *);
static void ocrLanguagesLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeClipboardText(int,id,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeKeyboardNotification(int,id,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeClipboardImage(id,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeAlert(id,id,int,TLinkTaskExecutionContext *);
static void alertLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_SHOW_ALERT_BOX=12};
NSDictionary *TLinkExecuteNativeDialog(id,id,id,id,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeClearDialog(TLinkTaskExecutionContext *);
static void dialogLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_DIALOG=42,TASK_CLEAR_DIALOG=43};
static void clipboardTextLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_TEXT_INPUT=24};
NSDictionary *TLinkExecuteNativeToast(int,NSString *,int,int,int,TLinkTaskExecutionContext *);
static void toastLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_SHOW_TOAST=22};
NSDictionary *TLinkExecuteNativeRadioState(int,BOOL,BOOL,TLinkTaskExecutionContext *);
static void radioLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_WIFI=55,TASK_BLUETOOTH=56};
static void auxRadioLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_AIRPLANE=57,TASK_CELLULAR_DATA=58};
static void deviceInfoLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_GET_DEVICE_INFO=25};
static void openUrlLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_OPEN_URL=54};
static void listBundlesLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_LIST_BUNDLES=53};
static void appOpenLegacyTask(UInt8 *,CFWriteStreamRef);
static void appKillLegacyTask(UInt8 *,CFWriteStreamRef);
static void appPathsLegacyTask(UInt8 *,CFWriteStreamRef);
static void appInfoLegacyTask(UInt8 *,CFWriteStreamRef);
static void appStateLegacyTask(UInt8 *,CFWriteStreamRef);
static void appPidLegacyTask(UInt8 *,CFWriteStreamRef);
enum {TASK_APP_PID=50,TASK_APP_STATE=32,TASK_APP_INFO=33,TASK_APP_KILL=31,TASK_APP_PATHS=52,TASK_PROCESS_BRING_FOREGROUND=11};
static NSString *mode;
static int calls, releases;
static std::string lastPayload;
static TLinkTaskExecutionContext *observed;
NSDictionary *TLinkExecuteNativeTouch(const TLinkNativeTouchRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeTouchBatch(const std::vector<TLinkNativeTouchRequest> &,TLinkTaskExecutionContext *);
static bool zx_handleNativeBatch(UInt8 *,NSError **);
NSDictionary *TLinkExecuteNativeFrameRelease(const TLinkNativeFrameReleaseRequest &,TLinkTaskExecutionContext *);
static void frameReleaseLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameCapture(const TLinkNativeFrameCaptureRequest &,TLinkTaskExecutionContext *);
static void frameCaptureLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static void captureRollbackLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static unsigned trackFrames=0;static int lastTrackedFrame=-1;
NSDictionary *TLinkExecuteNativeImageRelease(const TLinkNativeImageReleaseRequest &,TLinkTaskExecutionContext *);
static void imageReleaseLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static unsigned untrackImages=0;static int lastUntrackedImage=-1;
static unsigned untrackFrames=0,untrackAllFrames=0;static int lastUntrackedFrame=-1;
enum {TASK_NATIVE_BATCH=65,TASK_COLOR_PICKER=23,TASK_COLOR_SEARCHER=28,TASK_COLOR_IN_FRAME=69,TASK_FIND_IMAGE_IN_FRAME=68,TASK_OCR_TESSERACT_REGION=91,TASK_FRAME_RELEASE=67,TASK_IMAGE_OBJECT=48,TASK_FRAME_CAPTURE=66};
NSDictionary *TLinkExecuteNativeColorPick(const TLinkNativeColorPickRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeColorRange(const TLinkNativeColorRangeRequest &,TLinkTaskExecutionContext *);
static void colorRangeLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeColorPoints(const TLinkNativeColorPointsRequest &,TLinkTaskExecutionContext *);
static void colorPointsLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeColorMulti(const TLinkNativeColorMultiRequest &,TLinkTaskExecutionContext *);
static void colorMultiLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFramePick(const TLinkNativeFramePickRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeFramePickMany(const TLinkNativeFramePickManyRequest &,TLinkTaskExecutionContext *);
static void frameManyLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameImage(const TLinkNativeFrameImageRequest &,TLinkTaskExecutionContext *);
static void frameImageLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameOCR(const TLinkNativeFrameOCRRequest &,TLinkTaskExecutionContext *);
static void frameOCRLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameSearch(const TLinkNativeFrameSearchRequest &,TLinkTaskExecutionContext *);
static void frameSearchLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameColors(const TLinkNativeFrameColorsRequest &,TLinkTaskExecutionContext *);
static void frameColorsLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameMulti(const TLinkNativeFrameMultiRequest &,TLinkTaskExecutionContext *);
static void frameMultiLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static void processTaskWithContext(UInt8 *bytes, size_t length, CFWriteStreamRef stream, TLinkTaskExecutionContext *context) {
    ++calls; observed = context;
    lastPayload.assign(reinterpret_cast<char *>(bytes), length);
    assert(bytes[length] == 0 && [context nativeBudget] == TLinkCurrentNativeBudget());
    if([mode isEqualToString:@"dialogRuntime"]&&(lastPayload.compare(0,2,"42")==0||lastPayload.compare(0,2,"43")==0)){dialogLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"alertRuntime"]&&lastPayload.compare(0,2,"12")==0){alertLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"toastRuntime"]&&lastPayload.compare(0,2,"22")==0){toastLegacyTask(bytes,stream);return;}
    if(([mode isEqualToString:@"clipboardTextRuntime"]||[mode isEqualToString:@"keyboardNotificationRuntime"])&&lastPayload.compare(0,2,"24")==0){clipboardTextLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"ocrLanguagesRuntime"]&&lastPayload.compare(0,2,"91")==0){ocrLanguagesLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"auxRadioRuntime"]&&(lastPayload.compare(0,2,"57")==0||lastPayload.compare(0,2,"58")==0)){auxRadioLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"radioRuntime"]&&(lastPayload.compare(0,2,"55")==0||lastPayload.compare(0,2,"56")==0)){radioLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"deviceInfoRuntime"]&&lastPayload.compare(0,2,"25")==0){deviceInfoLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"openUrlRuntime"]&&lastPayload.compare(0,2,"54")==0){openUrlLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"listBundlesRuntime"]&&lastPayload.compare(0,2,"53")==0){listBundlesLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appOpenRuntime"]&&lastPayload.compare(0,2,"11")==0){appOpenLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appKillRuntime"]&&lastPayload.compare(0,2,"31")==0){appKillLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appPathsRuntime"]&&lastPayload.compare(0,2,"52")==0){appPathsLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appInfoRuntime"]&&lastPayload.compare(0,2,"33")==0){appInfoLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appStateRuntime"]&&lastPayload.compare(0,2,"32")==0){appStateLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"appPidRuntime"]&&lastPayload.compare(0,2,"50")==0){appPidLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"frontmostPidRuntime"]&&lastPayload=="51"){frontmostPidLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"indicatorRuntime"]&&lastPayload.compare(0,2,"26")==0){indicatorLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"keepAwakeRuntime"]&&lastPayload.compare(0,2,"40")==0){keepAwakeLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"hardwareKeyRuntime"]&&lastPayload.compare(0,2,"30")==0){hardwareKeyLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"frontmostRuntime"]&&(lastPayload=="34"||lastPayload=="35")){frontmostLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"pathRuntime"]&&(lastPayload=="44"||lastPayload=="45"||lastPayload=="46")){pathLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"imageCaptureRuntime"]&&lastPayload.compare(0,5,"481;;")==0){imageCaptureLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"imageCaptureRuntime"]&&lastPayload.compare(0,5,"483;;")==0){imageCaptureRollbackLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"imageOpenRuntime"]&&lastPayload.compare(0,5,"482;;")==0){imageOpenLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"imageOpenRuntime"]&&lastPayload.compare(0,5,"483;;")==0){imageOpenRollbackLegacyTask(bytes,stream);return;}
    if([mode isEqualToString:@"frameCaptureRuntime"]&&lastPayload.compare(0,2,"66")==0){frameCaptureLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameCaptureRuntime"]&&lastPayload.compare(0,2,"67")==0){captureRollbackLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"imageReleaseRuntime"]&&lastPayload.compare(0,5,"483;;")==0){imageReleaseLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameReleaseRuntime"]&&lastPayload.compare(0,2,"67")==0){frameReleaseLegacyTask(bytes,length,stream);return;}
    if (lastPayload.compare(0, 2, "67") == 0 || lastPayload.compare(0, 5, "483;;") == 0 || lastPayload.compare(0, 5, "300;;") == 0) {
        assert([context nativeBudget]->cleanup()); ++releases;
        notifyClient((UInt8 *)"0\r\n", stream); return;
    }
    if([mode isEqualToString:@"batchRuntime"]&&lastPayload.compare(0,2,"65")==0){
        NSError *error=nil;zx_handleNativeBatch(bytes+2,&error);
        notifyClient((UInt8 *)[(error.localizedDescription?:@"0\r\n") UTF8String],stream);return;
    }
    if([mode isEqualToString:@"frameEncodingOracle"]&&lastPayload.compare(0,2,"69")==0){
        // These probes only use invalid coord tokens; legacy transport decides encoding admission.
        notifyClient((UInt8 *)"1;;invalid_frame_color_parameters\r\n",stream);return;
    }
    if([mode isEqualToString:@"colorMultiRuntime"]&&lastPayload.compare(0,2,"28")==0){colorMultiLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"colorPointsRuntime"]&&lastPayload.compare(0,2,"28")==0){colorPointsLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"colorRangeRuntime"]&&lastPayload.compare(0,2,"28")==0){colorRangeLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameOCRRuntime"]&&lastPayload.compare(0,2,"91")==0){frameOCRLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameImageRuntime"]&&lastPayload.compare(0,2,"68")==0){frameImageLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameManyRuntime"]&&lastPayload.compare(0,2,"69")==0){frameManyLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameSearchRuntime"]&&lastPayload.compare(0,2,"69")==0){frameSearchLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameColorsRuntime"]&&lastPayload.compare(0,2,"69")==0){frameColorsLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameMultiRuntime"]&&lastPayload.compare(0,2,"69")==0){frameMultiLegacyTask(bytes,length,stream);return;}
    if ([mode isEqualToString:@"chunks"]) {
        notifyClient((UInt8 *)"0;;", stream);
        notifyClient((UInt8 *)"12345", stream);
        notifyClient((UInt8 *)"67890", stream); return;
    }
    if ([mode isEqualToString:@"wait"]) {
        assert(!TLinkNativeWaitNs(10000000000ULL));
        notifyClient((UInt8 *)"0\r\n", stream); return;
    }
    if ([mode isEqualToString:@"cancelAllocation"]) {
        [context.cancellationToken cancel]; notifyClient((UInt8 *)"0;;41\r\n", stream); return;
    }
    if ([mode isEqualToString:@"expireAllocation"]) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        notifyClient((UInt8 *)"0;;41\r\n", stream); return;
    }
    if ([mode isEqualToString:@"exception"]) [NSException raise:@"NativeTest" format:@"task throws"];
    notifyClient((UInt8 *)"0;;xin chào\r\n", stream);
}
#include "NativeHelpersUnderTest.inc"
#include "NativeFrameOCRResult.inc"
#include "fixtures/native-frame-ocr-result-legacy-v1.inc"
#include "fixtures/frame-ocr-result-cases.inc"
#include "fixtures/frame-capture-result-cases.inc"
#include "fixtures/image-open-result-cases.inc"
@interface TLinkInProcessNativeBridge : NSObject
- (TLinkJSNativeResponse *)legacyImageCapture:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (void)trackImageId:(int)imageId;
- (TLinkJSNativeResponse *)legacyImageOpen:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (void)trackFrameId:(int)frameId;
- (TLinkJSNativeResponse *)legacyFrameCapture:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (void)untrackImageId:(int)imageId;
- (TLinkJSNativeResponse *)legacyImageRelease:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (void)untrackFrameId:(int)frameId;
- (void)untrackAllFrameIds;
- (TLinkJSNativeResponse *)legacyFrameRelease:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyColorRange:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyLiveColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyLiveMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameSearch:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameMany:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameImage:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameOCR:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrontmost:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyPath:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyHardwareKey:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyKeepAwake:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyIndicator:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrontmostPid:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyAppQuery:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyListBundles:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyOpenUrl:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyDeviceInfo:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyOCRLanguages:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyClipboardText:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyToast:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyKeyboardNotification:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyClipboardImage:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyAlert:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyDialog:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyRadio:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
@end
@implementation TLinkInProcessNativeBridge
- (TLinkJSNativeResponse *)legacyDialog:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-dialog-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyAlert:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-alert-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyClipboardImage:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-clipboard-image-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyKeyboardNotification:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-keyboard-notification-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyToast:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-toast-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyClipboardText:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-clipboard-text-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyOCRLanguages:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-ocr-languages-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyRadio:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-radio-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyDeviceInfo:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-device-info-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyOpenUrl:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-open-url-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyListBundles:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-list-bundles-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyAppQuery:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-app-query-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrontmostPid:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frontmost-pid-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyIndicator:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-indicator-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyKeepAwake:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-keep-awake-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyHardwareKey:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-hardware-key-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyPath:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-path-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrontmost:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frontmost-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyImageCapture:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if(false){}
#include "fixtures/native-image-capture-legacy-v1.inc"
    return nil;
}
- (void)trackImageId:(int)imageId {++trackImages;lastTrackedImage=imageId;}
- (TLinkJSNativeResponse *)legacyImageOpen:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if(false){}
#include "fixtures/native-image-open-legacy-v1.inc"
    return nil;
}
- (void)trackFrameId:(int)frameId {++trackFrames;lastTrackedFrame=frameId;}
- (TLinkJSNativeResponse *)legacyFrameCapture:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if(false){}
#include "fixtures/native-frame-capture-legacy-v1.inc"
    return nil;
}
- (void)untrackImageId:(int)imageId {++untrackImages;lastUntrackedImage=imageId;}
- (TLinkJSNativeResponse *)legacyImageRelease:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if(false){}
#include "fixtures/native-image-release-legacy-v1.inc"
    return nil;
}
- (void)untrackFrameId:(int)frameId {++untrackFrames;lastUntrackedFrame=frameId;}
- (void)untrackAllFrameIds {++untrackAllFrames;}
- (TLinkJSNativeResponse *)legacyFrameRelease:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if(false){}
#include "fixtures/native-frame-release-legacy-v1.inc"
    return nil;
}
#include "NativeBridgeUnderTest.inc"
- (TLinkJSNativeResponse *)legacyFrameMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-multi-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyLiveMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-live-multi-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyLiveColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-live-colors-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyColorRange:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-color-range-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-colors-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameSearch:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-search-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameOCR:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-ocr-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameImage:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-image-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameMany:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-pick-many-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error {
#include "NativeRequestPreludeUnderTest.inc"
    id runtime=self;
    if (false) {}
#include "NativePressUnderTest.inc"
#include "NativeTouchBridgeUnderTest.inc"
#include "NativeColorBridgeUnderTest.inc"
#include "NativeColorRangeBridge.inc"
#include "NativeColorPointsBridge.inc"
#include "NativeColorMultiBridge.inc"
#include "NativeFrameImageBridge.inc"
#include "NativeFrameOCRBridge.inc"
#include "NativeFrameReleaseBridge.inc"
#include "NativeImageReleaseBridge.inc"
#include "NativeFrameCaptureBridge.inc"
#include "NativeImageOpenBridge.inc"
#include "NativeImageCaptureBridge.inc"
#include "NativeFrontmostBridge.inc"
#include "NativePathBridge.inc"
#include "NativeFramePickBridge.inc"
#include "NativeFrameManyBridge.inc"
#include "NativeFrameSearchBridge.inc"
#include "NativeFrameColorsBridge.inc"
#include "NativeFrameMultiBridge.inc"
#include "NativeBatchBridgeUnderTest.inc"
#include "NativeHardwareKeyBridge.inc"
#include "NativeKeepAwakeBridge.inc"
#include "NativeIndicatorBridge.inc"
#include "NativeFrontmostPidBridge.inc"
#include "NativeAppQueryBridge.inc"
#include "NativeListBundlesBridge.inc"
#include "NativeOpenUrlBridge.inc"
#include "NativeDeviceInfoBridge.inc"
#include "NativeOCRLanguagesBridge.inc"
#include "NativeClipboardTextBridge.inc"
#include "NativeAlertBridge.inc"
#include "NativeDialogBridge.inc"
#include "NativeToastBridge.inc"
#include "NativeRadioBridge.inc"
    return nil;
}
@end
@interface Screen : NSObject
+ (CGFloat)getScreenWidth;
+ (CGFloat)getScreenHeight;
+ (int)getScreenOrientation;
+ (CGFloat)getScale;
@end
@implementation Screen
+ (CGFloat)getScreenWidth { return 500; }
+ (CGFloat)getScreenHeight { return 1000; }
+ (int)getScreenOrientation { return 3; }
+ (CGFloat)getScale { return 2; }
@end
enum { TOUCH_UP = 0, TOUCH_DOWN = 1, TOUCH_MOVE = 2,
       TASK_PERFORM_TOUCH = 10, TASK_NATIVE_TAP = 62, TASK_NATIVE_SWIPE = 63, TASK_NATIVE_GESTURE = 64 };
static std::vector<TLinkTouchPoint> injected;
static TLinkCancellationToken *touchToken;
static int cancelAt;
static int throwAt=0;static bool throwCpp=false;
static bool fakeTiming = false;
static uint64_t fakeNow = 0, frameWork = 0, oversleep = 0;
static unsigned fakeWaits = 0;
static std::vector<uint64_t> frameTimes;
static bool performTouchFrame(const TLinkTouchPoint *points, int count) {
    assert(TLinkValidateTouchFrame(points, count));
    if (fakeTiming) {frameTimes.push_back(fakeNow);fakeNow += frameWork;}
    for (int i = 0; i < count; ++i) injected.push_back(points[i]);
    if (throwAt>0 && int(injected.size())==throwAt) {
        if(throwCpp)throw std::runtime_error("touch test");
        [NSException raise:@"TouchTest" format:@"injection throws"];
    }
    if (cancelAt > 0 && int(injected.size()) >= cancelAt) [touchToken cancel];
    return true;
}
static bool performTouchFromRawData(const UInt8 *bytes, size_t length) {
    TLinkTouchPoint points[kTLinkTouchMaxCount]; int count = 0;
    assert(TLinkParseTouchPayload(bytes, length, points, &count));return performTouchFrame(points, count);
}
static uint64_t touchClockNow(){return fakeTiming ? fakeNow : TLinkNativeNowNs();}
static bool touchWaitNs(uint64_t ns){
    if (!fakeTiming) return TLinkNativeWaitNs(ns);
    ++fakeWaits;fakeNow += ns + oversleep;return !TLinkNativeStopped();
}
// Controlled clock/wait only; compile the actual timeline and gesture bodies.
#define TLinkNativeNowNs touchClockNow
#define TLinkNativeWaitNs touchWaitNs
#include "../shared/TLinkGestureTiming.h"
#include "NativeGesturesUnderTest.inc"
#undef TLinkNativeNowNs
#undef TLinkNativeWaitNs
static bool licenseAllowed=true,stopInLicense=false;
static int licenseCalls=0,lastLicenseTask=0;
static unsigned licenseDelayMs=0;
static TLinkNativeBudgetPtr licenseBudget;
static BOOL TLinkRootfullLicenseTaskAllowed(NSInteger task,NSString **denial){
    ++licenseCalls;lastLicenseTask=int(task);licenseBudget=TLinkCurrentNativeBudget();
    assert(TLinkCurrentNativeBudget() && !TLinkCurrentNativeBudget()->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));
    if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed && denial)*denial=[NSString stringWithFormat:@"-1;;license_required task=%ld\r\n",(long)task];
    return licenseAllowed;
}
static int colorCalls=0,colorFault=0;static bool cancelColor=false;static NSString *colorError=nil;
static TLinkNativeBudgetPtr colorBudget;
static NSDictionary *getRGBAtPosition(int x,int y,NSError **error){
    ++colorCalls;colorBudget=TLinkCurrentNativeBudget();assert(colorBudget&&!colorBudget->capturesResponse());
    if(colorFault==1)[NSException raise:@"ColorFixture" format:@"read throws"];
    if(colorFault==2)throw std::runtime_error("color fixture");
    NSString *code=(x<0||y<0||x>=8192||y>=8192)?@"color_parameters_invalid":colorError;
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return nil;}
    if(cancelColor)[touchToken cancel];
    return @{@"red":@(x%256),@"green":@(y%256),@"blue":@((x+y)%256)};
}
static unsigned colorRangeCalls=0;static int colorRangeFault=0;static bool cancelRange=false;static NSString *colorRangeError=nil;
static TLinkNativeBudgetPtr colorRangeBudget;
static bool colorRangeValues(const TLinkNativeColorRangeRequest &search,TLinkColorResult &value,NSError **error){
    NSString *code=[colorRangeError isEqualToString:@"color_compute_busy"]?colorRangeError:(TLinkNativeColorRangeParameters(search)?colorRangeError:@"color_parameters_invalid");
    TLinkColorRect region;
    if(!code&&!TLinkColorRegion(8,6,search.x,search.y,search.width,search.height,false,region))code=@"color_region_invalid";
    if(!code){
        std::vector<uint8_t> rgba(size_t(region.width)*region.height*4);for(size_t i=0;i<rgba.size();i+=4){rgba[i]=10;rgba[i+1]=20;rgba[i+2]=30;rgba[i+3]=255;}
        const TLinkColorPoint low={0,0,search.redMin,search.greenMin,search.blueMin},high={0,0,search.redMax,search.greenMax,search.blueMax};
        TLinkColorRequest work(TLinkCurrentNativeBudget());const auto status=TLinkColorRangeScan(rgba.data(),region.width,region.height,search.skip,low,high,work,value);
        if(status==TLinkColorScan::Stopped)code=@"color_cancelled_or_timed_out";
        else if(status==TLinkColorScan::NoMatch)value.x=value.y=value.r=value.g=value.b=-1;
        else {value.x+=region.x;value.y+=region.y;}
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}
    return true;
}
static bool searchRGBRange(const TLinkNativeColorRangeRequest &search,TLinkColorResult &value,NSError **error){
    ++colorRangeCalls;colorRangeBudget=TLinkCurrentNativeBudget();assert(colorRangeBudget&&!colorRangeBudget->capturesResponse());
    if(colorRangeFault==1)[NSException raise:@"ColorRangeFixture" format:@"range throws"];
    if(colorRangeFault==2)throw std::runtime_error("color range fixture");
    const bool ok=colorRangeValues(search,value,error);if(cancelRange)[touchToken cancel];return ok;
}
static void colorRangeLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];
    assert(fields.count==12&&[fields[0] isEqualToString:@"1"]);int numbers[11]={};bool valid=true;
    for(unsigned i=0;i<11;++i){const bool parsed=TLinkColorInt([fields[i+1] UTF8String],numbers[i]);valid=valid&&parsed;}
    TLinkNativeColorRangeRequest r;r.x=numbers[0];r.y=numbers[1];r.width=numbers[2];r.height=numbers[3];r.redMin=numbers[4];r.redMax=numbers[5];r.greenMin=numbers[6];r.greenMax=numbers[7];r.blueMin=numbers[8];r.blueMax=numbers[9];r.skip=numbers[10];r.coordinatesValid=valid;
    TLinkColorResult value;NSError *error=nil;
    if(!colorRangeValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%d;;%d;;%d\r\n",value.x,value.y,value.r,value.g,value.b];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned colorPointsCalls=0;static int colorPointsFault=0;static bool cancelColorPoints=false;static NSString *colorPointsError=nil;
static TLinkNativeBudgetPtr colorPointsBudget;
static bool colorPointsValues(const TLinkNativeColorPointsRequest &check,bool &matched,NSError **error){
    NSString *code=[colorPointsError isEqualToString:@"color_compute_busy"]?colorPointsError:(TLinkNativeColorPointsParameters(check)?nil:@"color_parameters_invalid");
    if(!code){if(const char *tableError=TLinkNativeColorPointsTableError(check))code=[NSString stringWithUTF8String:tableError];}
    TLinkColorRect crop;
    if(!code&&!TLinkNativeColorPointsBounds(check.points,8192,8192,crop))code=@"color_point_out_of_bounds";
    if(!code)code=colorPointsError;
    if(!code&&!TLinkNativeColorPointsBounds(check.points,8,6,crop))code=@"color_point_out_of_bounds";
    if(!code){
        std::vector<uint8_t> rgba(size_t(crop.width)*crop.height*4);for(size_t i=0;i<rgba.size();i+=4){rgba[i]=10;rgba[i+1]=20;rgba[i+2]=30;rgba[i+3]=255;}
        TLinkColorRequest work(TLinkCurrentNativeBudget());if(!TLinkNativeColorPointsCompare(rgba.data(),crop.width,crop,check.points,check.mode,check.tolerance,work,matched))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}
    return true;
}
static bool testRGBPoints(const TLinkNativeColorPointsRequest &check,bool &matched,NSError **error){
    ++colorPointsCalls;colorPointsBudget=TLinkCurrentNativeBudget();assert(colorPointsBudget&&!colorPointsBudget->capturesResponse());
    if(colorPointsFault==1)[NSException raise:@"ColorPointsFixture" format:@"compare throws"];
    if(colorPointsFault==2)throw std::runtime_error("color points fixture");
    const bool ok=colorPointsValues(check,matched,error);if(cancelColorPoints)[touchToken cancel];return ok;
}
static void colorPointsLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];
    assert(fields.count==4&&[fields[0] isEqualToString:@"2"]);TLinkNativeColorPointsRequest r;r.mode=[fields[2] intValue];r.toleranceUnits=[fields[3] length];r.toleranceValid=TLinkColorDouble([fields[3] UTF8String],r.tolerance);
    NSString *table=fields[1];r.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.tableValid=r.tableValid&&valid;r.points.push_back(point);
    }
    bool matched=false;NSError *error=nil;if(!colorPointsValues(r,matched,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d\r\n",matched?1:0];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned colorMultiCalls=0;static int colorMultiFault=0;static bool cancelColorMulti=false;static NSString *colorMultiError=nil;
static TLinkNativeBudgetPtr colorMultiBudget;
static bool colorMultiValues(const TLinkNativeColorMultiRequest &search,TLinkColorResult &value,NSError **error){
    NSString *code=[colorMultiError isEqualToString:@"color_compute_busy"]?colorMultiError:(TLinkNativeColorMultiParameters(search)?nil:@"color_parameters_invalid");
    if(!code){if(const char *tableError=TLinkNativeColorPointsTableError(search.colors))code=[NSString stringWithUTF8String:tableError];}
    if(!code)code=colorMultiError;
    TLinkColorRect crop,anchors,region;
    if(!code&&!TLinkColorRegion(8,6,search.x,search.y,search.width,search.height,true,region))code=@"color_region_invalid";
    if(!code){value.x=value.y=-1;
        if(TLinkColorAnchors(8,6,region,search.colors.points,anchors,crop)){
            std::vector<uint8_t> rgba(size_t(crop.width)*crop.height*4);for(size_t i=0;i<rgba.size();i+=4){rgba[i]=10;rgba[i+1]=20;rgba[i+2]=30;rgba[i+3]=255;}
            TLinkColorRequest work(TLinkCurrentNativeBudget());const auto status=TLinkColorMultiScan(rgba.data(),crop.width,crop,anchors,search.colors.points,search.colors.mode,search.colors.tolerance,search.skip,work,value);
            if(status==TLinkColorScan::Stopped)code=@"color_cancelled_or_timed_out";else if(status==TLinkColorScan::NoMatch)value.x=value.y=-1;
        }
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}return true;
}
static bool searchRGBMulti(const TLinkNativeColorMultiRequest &search,TLinkColorResult &value,NSError **error){
    ++colorMultiCalls;colorMultiBudget=TLinkCurrentNativeBudget();assert(colorMultiBudget&&!colorMultiBudget->capturesResponse());
    if(colorMultiFault==1)[NSException raise:@"ColorMultiFixture" format:@"search throws"];
    if(colorMultiFault==2)throw std::runtime_error("color multi fixture");
    const bool ok=colorMultiValues(search,value,error);if(cancelColorMulti)[touchToken cancel];return ok;
}
static void colorMultiLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];
    assert(fields.count==9&&[fields[0] isEqualToString:@"3"]);TLinkNativeColorMultiRequest r;r.colors.mode=[fields[6] intValue];r.colors.toleranceUnits=[fields[7] length];r.colors.toleranceValid=TLinkColorDouble([fields[7] UTF8String],r.colors.tolerance);r.skip=[fields[8] intValue];
    int *dest[]={&r.x,&r.y,&r.width,&r.height};for(unsigned i=0;i<4;++i){bool valid=TLinkColorInt([fields[i+1] UTF8String],*dest[i]);r.coordinatesValid=r.coordinatesValid&&valid;}
    NSString *table=fields[5];r.colors.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.colors.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.colors.tableValid=r.colors.tableValid&&valid;r.colors.points.push_back(point);
    }
    TLinkColorResult value;NSError *error=nil;if(!colorMultiValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d\r\n",value.x,value.y];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameReads=0;static int frameReadFault=0;static bool cancelFrameRead=false;static NSString *frameReadError=nil;
static TLinkNativeBudgetPtr frameBudget;static TLinkNativeFramePickRequest observedFramePick;
static bool readFramePixel(const TLinkNativeFramePickRequest &pick,TLinkNativeFramePickValue &value,NSError **error){
    ++frameReads;observedFramePick=pick;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame fixture");
    NSString *code=TLinkFramePickParameters(pick)?frameReadError:@"invalid_frame_color_parameters";
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    if(cancelFrameRead)[touchToken cancel];
    value.red=1;value.green=2;value.blue=3;value.ageMs=7;value.totalMs=1.23456;return true;
}
static unsigned frameManyReads=0;static TLinkNativeFramePickManyRequest observedFrameMany;
static bool frameManyValues(const TLinkNativeFramePickManyRequest &pick,TLinkNativeFramePickManyValue &value,NSError **error){
    NSString *code=TLinkFramePickParameters(pick.frame)?frameReadError:@"invalid_frame_color_parameters";
    if(!code&&(pick.pointCount>512||pick.tableUnits>32768))code=@"point_table_limit";
    if(!code){for(const auto &point:pick.points){
        TLinkNativeFrameColor pixel;
        if(!TLinkFrameColorCoordinate(point.x,2,pick.frame.pointCoord,pixel.x)||!TLinkFrameColorCoordinate(point.y,2,pick.frame.pointCoord,pixel.y)){code=@"invalid_pick_many_point";break;}
        if(pixel.x<0||pixel.y<0||pixel.x>=8192||pixel.y>=8192){code=@"point_out_of_bounds";break;}
        pixel.red=pixel.x%256;pixel.green=pixel.y%256;pixel.blue=3;value.colors.push_back(pixel);
    }}
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool readFramePixels(const TLinkNativeFramePickManyRequest &pick,TLinkNativeFramePickManyValue &value,NSError **error){
    ++frameManyReads;observedFrameMany=pick;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameManyFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame many fixture");
    const bool ok=frameManyValues(pick,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameManyLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==5&&[fields[1] isEqualToString:@"pick_many"]);
    TLinkNativeFramePickManyRequest pick;pick.frame.frameId=[fields[0] intValue];pick.frame.maxAgeMs=[fields[4] intValue];
    NSString *coord=[fields[3] lowercaseString];pick.frame.pointCoord=[coord isEqualToString:@"point"];pick.frame.validCoord=pick.frame.pointCoord||[coord isEqualToString:@"pixel"];
    for(NSString *item in [fields[2] componentsSeparatedByString:@"|"]){NSArray *xy=[item componentsSeparatedByString:@","];assert(xy.count==2);pick.append([xy[0] doubleValue],[xy[1] doubleValue]);}
    TLinkNativeFramePickManyValue value;NSError *error=nil;
    if(!frameManyValues(pick,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSMutableArray *rows=[NSMutableArray array];for(const auto &pixel:value.colors)[rows addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d",pixel.x,pixel.y,pixel.red,pixel.green,pixel.blue]];
    NSString *raw=[NSString stringWithFormat:@"0;;%@;;%llu;;%.3f;;%.3f\r\n",[rows componentsJoinedByString:@"|"],(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
    notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameSearchReads=0;
static bool frameSearchValues(const TLinkNativeFrameSearchRequest &search,TLinkNativeFrameSearchValue &value,NSError **error){
    NSString *code=TLinkFrameSearchParameters(search)?frameReadError:@"invalid_frame_color_parameters";
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});const auto status=TLinkFrameSearchScan(bgra.data(),8,8,40,2,search,work,value);
        if(status==TLinkFrameSearchStatus::CoordinateInvalid)code=@"frame_coordinate_invalid";
        if(status==TLinkFrameSearchStatus::Stopped)code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool searchFrameColor(const TLinkNativeFrameSearchRequest &search,TLinkNativeFrameSearchValue &value,NSError **error){
    ++frameSearchReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameSearchFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame search fixture");
    const bool ok=frameSearchValues(search,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameSearchLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==15&&[fields[1] isEqualToString:@"search_single"]);
    TLinkNativeFrameSearchRequest r;r.frame.frameId=[fields[0] intValue];r.frame.maxAgeMs=[fields[14] intValue];
    NSString *coord=[fields[13] lowercaseString];r.frame.pointCoord=[coord isEqualToString:@"point"];r.frame.validCoord=r.frame.pointCoord||[coord isEqualToString:@"pixel"];
    r.x=[fields[2] doubleValue];r.y=[fields[3] doubleValue];r.width=[fields[4] doubleValue];r.height=[fields[5] doubleValue];
    r.redMin=[fields[6] intValue];r.redMax=[fields[7] intValue];r.greenMin=[fields[8] intValue];r.greenMax=[fields[9] intValue];r.blueMin=[fields[10] intValue];r.blueMax=[fields[11] intValue];r.skip=[fields[12] intValue];
    TLinkNativeFrameSearchValue value;NSError *error=nil;
    if(!frameSearchValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f\r\n",value.x,value.y,value.red,value.green,value.blue,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
    notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameColorsReads=0;
static bool frameColorsValues(const TLinkNativeFrameColorsRequest &check,TLinkNativeFrameColorsValue &value,NSError **error){
    NSString *code=TLinkFrameColorsParameters(check)?frameReadError:@"invalid_frame_color_parameters";
    if(!code){if(const char *tableError=TLinkFrameColorsTableError(check))code=[NSString stringWithUTF8String:tableError];}
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});if(!TLinkFrameColorsEvaluate(bgra.data(),8,8,40,2,check.points,check.frame.pointCoord,check.mode,check.tolerance,work,value.matched))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool testFrameColors(const TLinkNativeFrameColorsRequest &check,TLinkNativeFrameColorsValue &value,NSError **error){
    ++frameColorsReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameColorsFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame colors fixture");
    const bool ok=frameColorsValues(check,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameColorsLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==7&&[fields[1] isEqualToString:@"is_colors"]);
    TLinkNativeFrameColorsRequest r;r.frame.frameId=[fields[0] intValue];r.frame.maxAgeMs=[fields[6] intValue];r.mode=[fields[3] intValue];
    r.toleranceValid=TLinkColorDouble([fields[4] UTF8String],r.tolerance);r.toleranceUnits=[fields[4] length];
    NSString *coord=[fields[5] lowercaseString];r.frame.pointCoord=[coord isEqualToString:@"point"];r.frame.validCoord=r.frame.pointCoord||[coord isEqualToString:@"pixel"];
    NSString *table=fields[2];r.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.tableValid=r.tableValid&&valid;r.points.push_back(point);
    }
    TLinkNativeFrameColorsValue value;NSError *error=nil;
    if(!frameColorsValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%llu;;%.3f;;%.3f\r\n",value.matched?1:0,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameMultiReads=0;
static bool frameMultiValues(const TLinkNativeFrameMultiRequest &search,TLinkNativeFrameMultiValue &value,NSError **error){
    NSString *code=TLinkFrameMultiParameters(search)?frameReadError:@"invalid_frame_color_parameters";TLinkColorRect region;
    if(!code&&!TLinkFrameMultiRegion(8,8,2,search,region))code=@"frame_coordinate_invalid";
    if(!code){if(const char *tableError=TLinkFrameColorsTableError(search.colors))code=[NSString stringWithUTF8String:tableError];}
    auto points=search.colors.points;
    if(!code&&!TLinkFrameMultiOffsets(points,2,search.colors.frame.pointCoord))code=@"frame_coordinate_invalid";
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});if(!TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,search.colors.mode,search.colors.tolerance,search.skip,work,value))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool findFrameColors(const TLinkNativeFrameMultiRequest &search,TLinkNativeFrameMultiValue &value,NSError **error){
    ++frameMultiReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameMultiFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame multi fixture");
    const bool ok=frameMultiValues(search,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameMultiLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==12&&[fields[1] isEqualToString:@"find_multi_point"]);
    TLinkNativeFrameMultiRequest r;r.colors.frame.frameId=[fields[0] intValue];r.colors.frame.maxAgeMs=[fields[11] intValue];r.colors.mode=[fields[7] intValue];r.skip=[fields[9] intValue];
    r.x=[fields[2] doubleValue];r.y=[fields[3] doubleValue];r.width=[fields[4] doubleValue];r.height=[fields[5] doubleValue];
    r.colors.toleranceValid=TLinkColorDouble([fields[8] UTF8String],r.colors.tolerance);r.colors.toleranceUnits=[fields[8] length];
    NSString *coord=[fields[10] lowercaseString];r.colors.frame.pointCoord=[coord isEqualToString:@"point"];r.colors.frame.validCoord=r.colors.frame.pointCoord||[coord isEqualToString:@"pixel"];
    NSString *table=fields[6];r.colors.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.colors.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.colors.tableValid=r.colors.tableValid&&valid;r.colors.points.push_back(point);
    }
    TLinkNativeFrameMultiValue value;NSError *error=nil;
    if(!frameMultiValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%llu;;%.3f;;%.3f\r\n",value.x,value.y,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameImageCalls=0;static int frameImageFault=0;static bool cancelFrameImage=false;static NSString *frameImageError=nil;
static TLinkNativeBudgetPtr frameImageBudget;
static bool frameImageValues(const TLinkNativeFrameImageRequest &search,TLinkNativeFrameImageValue &value,NSError **error){
    NSString *code=TLinkNativeFrameImageParameters(search)?frameImageError:@"invalid_image_parameters";
    int x=0,y=0,w=0,h=0;
    if(!code&&(!TLinkFrameColorCoordinate(search.x,2,search.pointCoord,x)||!TLinkFrameColorCoordinate(search.y,2,search.pointCoord,y)||!TLinkFrameColorCoordinate(search.width,2,search.pointCoord,w)||!TLinkFrameColorCoordinate(search.height,2,search.pointCoord,h)))code=@"frame_coordinate_invalid";
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}
    TLinkColorRect region;assert(TLinkColorRegion(8,8,x,y,w,h,true,region));value.ageMs=7;value.totalMs=1.23456;value.score=.876543;
    if(search.acceptable<=.9&&region.width>=3&&region.height>=5){value.x=region.x;value.y=region.y;value.width=3;value.height=5;value.centerX=value.x+1.5;value.centerY=value.y+2.5;}
    return true;
}
static bool matchImageInFrame(const TLinkNativeFrameImageRequest &search,TLinkNativeFrameImageValue &value,NSError **error){
    ++frameImageCalls;frameImageBudget=TLinkCurrentNativeBudget();assert(frameImageBudget&&!frameImageBudget->capturesResponse());
    if(frameImageFault==1)[NSException raise:@"FrameImageFixture" format:@"match throws"];
    if(frameImageFault==2)throw std::runtime_error("frame image fixture");
    const bool ok=frameImageValues(search,value,error);if(cancelFrameImage)[touchToken cancel];return ok;
}
static void frameImageLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==13);
    TLinkNativeFrameImageRequest r;r.frameId=[fields[0] intValue];r.imageId=[fields[1] intValue];
    for(unsigned i=0;i<4;++i){r.regionPart(i,[fields[i+2] UTF8String],[fields[i+2] length]);r.scalarPart(i,[fields[i+6] UTF8String],[fields[i+6] length]);}
    r.pixelSkip=[fields[10] intValue];r.maxAgeMs=[fields[12] intValue];NSString *coord=[fields[11] lowercaseString];r.pointCoord=[coord isEqualToString:@"point"];r.validCoord=r.pointCoord||[coord isEqualToString:@"pixel"];
    TLinkNativeFrameImageValue value;NSError *error=nil;if(!frameImageValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=value.x<0?[NSString stringWithFormat:@"0;;-1;;-1;;0;;0;;-1;;-1;;%.4f;;%llu;;%.3f;;%.3f\r\n",value.score,(unsigned long long)value.ageMs,value.totalMs,value.totalMs]:[NSString stringWithFormat:@"0;;%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f;;%llu;;%.3f;;%.3f\r\n",value.x,value.y,value.width,value.height,value.centerX,value.centerY,value.score,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameOCRCalls=0;static int frameOCRFault=0;static bool cancelFrameOCR=false;static NSString *frameOCRError=nil;
static TLinkNativeBudgetPtr frameOCRBudget;
static bool customOCRResult=false;static TLinkNativeFrameOCRValue publishedOCRResult;
static bool frameOCRValues(const TLinkNativeFrameOCRRequest &r,TLinkNativeFrameOCRValue &value,NSError **error){
    if(customOCRResult){value=publishedOCRResult;return true;}
    if(frameOCRError){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@;;%@\r\n",frameOCRError,TLinkautoJSBase64Encode(@"controlled OCR error")]}];return false;}
    NSString *text=[NSString stringWithFormat:@"%@|%@|%@|%u|%d|%d|%d|%d|%d|%d|%d|%d|%llu",r.lang.length?r.lang:@"vie",r.coord.length?r.coord:@"pixel",r.whitelist?:@"",r.frameId,r.x,r.y,r.width,r.height,r.oem,r.psm,r.scaleUp,r.thresholdMode,(unsigned long long)(r.maxAgeMs?r.maxAgeMs:1000)];
    value=TLinkFormatFrameOCRValue(text,83.12,42,1.235,2.346,3.457);return true;
}
bool recognizeFrameWithTesseract(const TLinkNativeFrameOCRRequest &r,TLinkNativeFrameOCRValue &value,NSError **error){
    ++frameOCRCalls;frameOCRBudget=TLinkCurrentNativeBudget();assert(frameOCRBudget&&!frameOCRBudget->capturesResponse());
    if(frameOCRFault==1)[NSException raise:@"FrameOCRFixture" format:@"OCR throws"];
    if(frameOCRFault==2)throw std::runtime_error("frame OCR fixture");
    const bool ready=frameOCRValues(r,value,error);if(cancelFrameOCR)[touchToken cancel];return ready;
}
static void frameOCRLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==13);
    TLinkNativeFrameOCRRequest r;r.frameId=uint32_t([fields[0] intValue]);r.x=[fields[1] intValue];r.y=[fields[2] intValue];r.width=[fields[3] intValue];r.height=[fields[4] intValue];r.lang=[fields[5] length]?fields[5]:@"vie";r.oem=[fields[6] intValue];r.psm=[fields[7] intValue];r.whitelist=TLinkautoJSBase64Decode(fields[8]);r.scaleUp=[fields[9] intValue];r.thresholdMode=[fields[10] intValue];r.coord=[fields[11] length]?fields[11]:@"pixel";r.maxAgeMs=uint64_t(MAX(0,[fields[12] longLongValue]));if(!r.maxAgeMs)r.maxAgeMs=1000;
    NSError *error=nil;TLinkNativeFrameOCRValue value;const bool ready=frameOCRValues(r,value,&error);NSString *raw=error.localizedDescription?:[NSString stringWithFormat:@"0;;%@\r\n",ready?value.body:@""];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static bool hugeCaptureReply=false;
static unsigned frameCaptureCalls=0;static int frameCaptureFault=0;static bool cancelFrameCapture=false;static unsigned frameCaptureDelay=0;static NSString *frameCaptureError=nil;
static TLinkNativeFrameCaptureRequest observedFrameCapture;static TLinkNativeBudgetPtr frameCaptureBudget;
static std::set<uint32_t> capturedFrames;static TLinkCancellationToken *captureToken;
static bool frameCaptureValues(const TLinkNativeFrameCaptureRequest &r,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error){
    observedFrameCapture=r;
    if(frameCaptureError){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",frameCaptureError]}];return false;}
    publishedId=41;capturedFrames.insert(publishedId);
    value.id=publishedId;value.width=8;value.height=8;value.bytesPerRow=32;value.scale=2.125;
    value.hasBGRA=r.bgra||!r.gray;value.hasGray=r.gray||!r.bgra;value.capturedAtMs=123456;
    value.captureMs=1.125;value.bgraMs=2.250;value.grayMs=3.375;value.totalMs=6.750;
    if(hugeCaptureReply)value.captureMs=value.bgraMs=value.grayMs=value.totalMs=1.7976931348623157e308;
    return true;
}
bool captureStoredFrame(const TLinkNativeFrameCaptureRequest &r,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error){
    ++frameCaptureCalls;frameCaptureBudget=TLinkCurrentNativeBudget();assert(frameCaptureBudget&&!frameCaptureBudget->capturesResponse());
    if(frameCaptureFault==1)[NSException raise:@"CaptureFixture" format:@"before publish"];
    if(frameCaptureFault==2)throw std::runtime_error("before publish");
    const bool ready=frameCaptureValues(r,publishedId,value,error);
    if(frameCaptureFault==3)[NSException raise:@"CaptureFixture" format:@"after publish"];
    if(frameCaptureFault==4)throw std::runtime_error("after publish");
    if(cancelFrameCapture)[captureToken cancel];if(frameCaptureDelay)std::this_thread::sleep_for(std::chrono::milliseconds(frameCaptureDelay));return ready;
}
static void frameCaptureLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *raw=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[raw componentsSeparatedByString:@";;"];
    TLinkNativeFrameCaptureRequest r;r.gray=[fields[0] intValue]!=0;r.bgra=[fields[1] intValue]!=0;r.ttlMs=uint64_t(MAX(0,[fields[2] longLongValue]));
    if(fields.count>3&&[fields[3] length])r.sessionId=[fields[3] UTF8String]?:"";
    if(fields.count>4&&[fields[4] length])r.runId=[fields[4] UTF8String]?:"";
    if(fields.count>5&&[fields[5] length])r.runtime=[fields[5] UTF8String]?:"";
    NSError *error=nil;uint32_t id=0;TLinkNativeFrameCaptureValue value;const bool ready=frameCaptureValues(r,id,value,&error);NSString *body=ready?legacyFrameCaptureBody(value):nil;NSString *reply=error.localizedDescription?:[NSString stringWithFormat:@"0;;%@\r\n",body?:@""];notifyClient((UInt8 *)reply.UTF8String,stream);
}
static void captureRollbackLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    (void)length;assert(TLinkCurrentNativeBudget()->cleanup());NSString *raw=[[NSString alloc] initWithUTF8String:(char *)bytes+2];capturedFrames.erase(uint32_t(raw.intValue));notifyClient((UInt8 *)"0;;1\r\n",stream);
}
static unsigned frameReleaseCalls=0;static int frameReleaseFault=0;static size_t frameReleaseCount=1;
static TLinkNativeFrameReleaseRequest observedFrameRelease;
static TLinkNativeBudgetPtr frameReleaseBudget;
size_t releaseStoredFrames(const TLinkNativeFrameReleaseRequest &request){
    ++frameReleaseCalls;observedFrameRelease=request;frameReleaseBudget=TLinkCurrentNativeBudget();
    assert(frameReleaseBudget&&frameReleaseBudget->cleanup()&&!frameReleaseBudget->capturesResponse()&&frameReleaseBudget->response().capacity()==0);
    if([mode isEqualToString:@"frameCaptureRuntime"])return capturedFrames.erase(request.frameId);
    if(frameReleaseFault==1)[NSException raise:@"FrameReleaseFixture" format:@"release throws"];
    if(frameReleaseFault==2)throw std::runtime_error("release fixture");
    return frameReleaseCount;
}
static void frameReleaseLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    assert(TLinkCurrentNativeBudget()->cleanup());
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[[payload stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@";;"];
    TLinkNativeFrameReleaseRequest r;r.all=[fields[0] isEqualToString:@"all"];r.frameId=uint32_t([fields[0] intValue]);r.scoped=fields.count>=4;
    if(r.scoped){r.sessionId=[fields[1] UTF8String]?:"";r.runId=[fields[2] UTF8String]?:"";r.runtime=[fields[3] UTF8String]?:"";}observedFrameRelease=r;
    NSString *raw=[NSString stringWithFormat:@"0;;%lu\r\n",(unsigned long)frameReleaseCount];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned imageOpenCalls=0;static int imageOpenFault=0;static bool cancelImageOpen=false,hugeImageOpenReply=false;static unsigned imageOpenDelay=0;
static NSString *imageOpenError=nil;static TLinkNativeImageOpenRequest observedImageOpen;static TLinkNativeBudgetPtr imageOpenBudget;
static std::set<uint32_t> openedImages;static TLinkCancellationToken *imageOpenToken;
static bool imageOpenValues(const TLinkNativeImageOpenRequest &r,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error){
    observedImageOpen=r;
    if(imageOpenError){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",imageOpenError]}];return false;}
    publishedId=41;openedImages.insert(41);value.id=41;value.width=2;value.height=3;return true;
}
bool openStoredImage(const TLinkNativeImageOpenRequest &r,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error){
    ++imageOpenCalls;imageOpenBudget=TLinkCurrentNativeBudget();assert(imageOpenBudget&&!imageOpenBudget->capturesResponse());
    if(imageOpenFault==1)[NSException raise:@"ImageOpenFixture" format:@"before publish"];
    if(imageOpenFault==2)throw std::runtime_error("before publish");
    const bool ready=imageOpenValues(r,publishedId,value,error);
    if(imageOpenFault==3)[NSException raise:@"ImageOpenFixture" format:@"after publish"];
    if(imageOpenFault==4)throw std::runtime_error("after publish");
    if(imageOpenFault==9)return false;
    if(cancelImageOpen)[imageOpenToken cancel];if(imageOpenDelay)std::this_thread::sleep_for(std::chrono::milliseconds(imageOpenDelay));return ready;
}
static void imageOpenLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    (void)length;NSArray *fields=[[NSString stringWithFormat:@"%s",(const char *)bytes+2] componentsSeparatedByString:@";;"];
    TLinkNativeImageOpenRequest r;r.path=fields[1];
    if(fields.count>2&&[fields[2] length])r.sessionId=[fields[2] UTF8String]?:"";
    if(fields.count>3&&[fields[3] length])r.runId=[fields[3] UTF8String]?:"";
    if(fields.count>4&&[fields[4] length])r.runtime=[fields[4] UTF8String]?:"";
    NSError *error=nil;uint32_t id=0;TLinkNativeImageValue value;const bool ready=imageOpenValues(r,id,value,&error);NSString *body=ready?legacyImageOpenBody(value):nil;NSString *raw=error.localizedDescription?:[NSString stringWithFormat:@"0;;%@\r\n",body?:@""];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static void imageOpenRollbackLegacyTask(UInt8 *bytes,CFWriteStreamRef stream){
    assert(TLinkCurrentNativeBudget()->cleanup());NSArray *fields=[[NSString stringWithFormat:@"%s",(const char *)bytes+2] componentsSeparatedByString:@";;"];
    openedImages.erase(uint32_t([fields[1] intValue]));notifyClient((UInt8 *)"0;;1\r\n",stream);
}
static unsigned imageCaptureCalls=0;static int imageCaptureFault=0;static bool cancelImageCapture=false,hugeImageCaptureReply=false;static unsigned imageCaptureDelay=0;
static NSString *imageCaptureError=nil;static TLinkNativeImageCaptureRequest observedImageCapture;static TLinkNativeBudgetPtr imageCaptureBudget;
static std::set<uint32_t> capturedImages;static TLinkCancellationToken *imageCaptureToken;
static bool imageCaptureValues(const TLinkNativeImageCaptureRequest &r,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error){
    observedImageCapture=r;
    if(imageCaptureError){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",imageCaptureError]}];return false;}
    publishedId=41;capturedImages.insert(41);value.id=41;value.width=2;value.height=3;return true;
}
bool captureStoredImage(const TLinkNativeImageCaptureRequest &r,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error){
    ++imageCaptureCalls;imageCaptureBudget=TLinkCurrentNativeBudget();assert(imageCaptureBudget&&!imageCaptureBudget->capturesResponse());
    if(imageCaptureFault==1)[NSException raise:@"ImageCaptureFixture" format:@"before publish"];
    if(imageCaptureFault==2)throw std::runtime_error("before publish");
    const bool ready=imageCaptureValues(r,publishedId,value,error);
    if(imageCaptureFault==3)[NSException raise:@"ImageCaptureFixture" format:@"after publish"];
    if(imageCaptureFault==4)throw std::runtime_error("after publish");
    if(imageCaptureFault==9)return false;
    if(cancelImageCapture)[imageCaptureToken cancel];if(imageCaptureDelay)std::this_thread::sleep_for(std::chrono::milliseconds(imageCaptureDelay));return ready;
}
static void imageCaptureLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    (void)length;NSArray *fields=[[NSString stringWithFormat:@"%s",(const char *)bytes+2] componentsSeparatedByString:@";;"];
    TLinkNativeImageCaptureRequest r;r.x=[fields[1] intValue];r.y=[fields[2] intValue];r.width=[fields[3] intValue];r.height=[fields[4] intValue];
    if(fields.count>5&&[fields[5] length])r.sessionId=[fields[5] UTF8String]?:"";
    if(fields.count>6&&[fields[6] length])r.runId=[fields[6] UTF8String]?:"";
    if(fields.count>7&&[fields[7] length])r.runtime=[fields[7] UTF8String]?:"";
    NSError *error=nil;uint32_t id=0;TLinkNativeImageValue value;const bool ready=imageCaptureValues(r,id,value,&error);NSString *body=ready?legacyImageOpenBody(value):nil;NSString *raw=error.localizedDescription?:[NSString stringWithFormat:@"0;;%@\r\n",body?:@""];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static void imageCaptureRollbackLegacyTask(UInt8 *bytes,CFWriteStreamRef stream){
    assert(TLinkCurrentNativeBudget()->cleanup());NSArray *fields=[[NSString stringWithFormat:@"%s",(const char *)bytes+2] componentsSeparatedByString:@";;"];
    capturedImages.erase(uint32_t([fields[1] intValue]));notifyClient((UInt8 *)"0;;1\r\n",stream);
}
static unsigned imageReleaseCalls=0;static int imageReleaseFault=0;static size_t imageReleaseCount=1;
static TLinkNativeImageReleaseRequest observedImageRelease;
static TLinkNativeBudgetPtr imageReleaseBudget;
size_t releaseStoredImages(const TLinkNativeImageReleaseRequest &request){
    ++imageReleaseCalls;observedImageRelease=request;imageReleaseBudget=TLinkCurrentNativeBudget();
    assert(imageReleaseBudget&&imageReleaseBudget->cleanup()&&!imageReleaseBudget->capturesResponse()&&imageReleaseBudget->response().capacity()==0);
    if([mode isEqualToString:@"imageOpenRuntime"])return openedImages.erase(request.imageId);
    if([mode isEqualToString:@"imageCaptureRuntime"])return capturedImages.erase(request.imageId);
    if(imageReleaseFault==1)[NSException raise:@"ImageReleaseFixture" format:@"release throws"];
    if(imageReleaseFault==2)throw std::runtime_error("image release fixture");
    return imageReleaseCount;
}
static void imageReleaseLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    (void)length;assert(TLinkCurrentNativeBudget()->cleanup());
    NSArray *fields=[[NSString stringWithFormat:@"%s",(const char *)bytes+2] componentsSeparatedByString:@";;"];
    TLinkNativeImageReleaseRequest r;r.imageId=uint32_t([fields[1] intValue]);r.scoped=fields.count>=5;
    if(r.scoped){r.sessionId=[fields[2] UTF8String]?:"";r.runId=[fields[3] UTF8String]?:"";r.runtime=[fields[4] UTF8String]?:"";}observedImageRelease=r;
    NSString *raw=[NSString stringWithFormat:@"0;;%lu\r\n",(unsigned long)imageReleaseCount];notifyClient((UInt8 *)raw.UTF8String,stream);
}
// Match Image.h: OpenCV leaves these macros undefined in production Task.xm.
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeTouchEntryUnderTest.inc"
#include "NativeColorEntryUnderTest.inc"
#include "NativeColorRangeEntry.inc"
#include "NativeColorPointsEntry.inc"
#include "NativeColorMultiEntry.inc"
#include "NativeFrameImageEntry.inc"
#include "NativeFrameOCREntry.inc"
#include "NativeFramePickEntry.inc"
#include "NativeFrameManyEntry.inc"
#include "NativeFrameSearchEntry.inc"
#include "NativeFrameColorsEntry.inc"
#include "NativeFrameMultiEntry.inc"
#include "NativeFrameReleaseEntry.inc"
#include "NativeImageReleaseEntry.inc"
static NSDictionary *fixtureImageCaptureResult(const TLinkNativeImageValue &v){
    if(imageCaptureFault==5)[NSException raise:@"ImageCaptureFixture" format:@"format result"];
    if(imageCaptureFault==6)throw std::runtime_error("format result");
    NSDictionary *result=TLinkNativeImageResult(v);
    if(imageCaptureFault==7)[imageCaptureToken cancel];
    if(imageCaptureFault==8)std::this_thread::sleep_for(std::chrono::milliseconds(30));
    if(hugeImageCaptureReply){NSMutableDictionary *oversized=[result mutableCopy];oversized[@"raw"]=[result[@"raw"] stringByPaddingToLength:2048 withString:@"x" startingAtIndex:0];return oversized;}
    return result;
}
#define TLinkNativeImageResult fixtureImageCaptureResult
#include "NativeImageCaptureEntry.inc"
#undef TLinkNativeImageResult
static NSDictionary *fixtureImageOpenResult(const TLinkNativeImageValue &v){
    if(imageOpenFault==5)[NSException raise:@"ImageOpenFixture" format:@"format result"];
    if(imageOpenFault==6)throw std::runtime_error("format result");
    NSDictionary *result=TLinkNativeImageResult(v);
    if(imageOpenFault==7)[imageOpenToken cancel];
    if(imageOpenFault==8)std::this_thread::sleep_for(std::chrono::milliseconds(30));
    if(hugeImageOpenReply){NSMutableDictionary *oversized=[result mutableCopy];oversized[@"raw"]=[result[@"raw"] stringByPaddingToLength:2048 withString:@"x" startingAtIndex:0];return oversized;}
    return result;
}
#define TLinkNativeImageResult fixtureImageOpenResult
#include "NativeImageOpenEntry.inc"
#undef TLinkNativeImageResult
static NSDictionary *fixtureFrameCaptureResult(const TLinkNativeFrameCaptureValue &v){
    if(frameCaptureFault==5)[NSException raise:@"CaptureFixture" format:@"format result"];
    if(frameCaptureFault==6)throw std::runtime_error("format result");
    NSDictionary *result=TLinkNativeFrameCaptureResult(v);
    if(frameCaptureFault==7)[captureToken cancel];
    return result;
}
#define TLinkNativeFrameCaptureResult fixtureFrameCaptureResult
#include "NativeFrameCaptureEntry.inc"
#undef TLinkNativeFrameCaptureResult
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static TLinkTaskExecutionContext *parent(double timeout = 1, NSUInteger cap = 1024 * 1024) {
    auto context = [TLinkTaskExecutionContext new];
    context.cancellationToken = [TLinkCancellationToken new];
    context.defaultTimeoutSeconds = timeout; context.defaultMaxOutputBytes = cap;
    context.ownerSessionId = @"session"; context.ownerRunId = @"run"; context.ownerRuntime = @"test";
    return context;
}
static void failure(NSDictionary *result, NSString *code, unsigned callerLine = __builtin_LINE()) {
    NSArray *parts=result[@"parts"];
    const bool matches=![result[@"ok"] boolValue]&&parts.count>1&&[parts[1] isEqualToString:code];
    if(!matches)std::fprintf(stderr,"native bridge failure at line %u: expected %s, received %s\n",callerLine,code.UTF8String ?: "(nil)",[[result description] UTF8String] ?: "(nil)");
    assert(matches);
}
#include "native-frontmost-runtime-fixture.inc"
#include "native-path-runtime-fixture.inc"
#include "native-hardware-key-runtime-fixture.inc"
#include "native-keep-awake-runtime-fixture.inc"
#include "native-indicator-runtime-fixture.inc"
#include "native-frontmost-pid-runtime-fixture.inc"
#include "native-app-pid-runtime-fixture.inc"
#include "native-app-state-runtime-fixture.inc"
#include "native-app-info-runtime-fixture.inc"
#include "native-app-paths-runtime-fixture.inc"
#include "native-app-kill-runtime-fixture.inc"
#include "native-app-open-runtime-fixture.inc"
#include "native-list-bundles-runtime-fixture.inc"
#include "native-open-url-runtime-fixture.inc"
#include "native-device-info-runtime-fixture.inc"
#include "native-radio-runtime-fixture.inc"
#include "native-aux-radio-runtime-fixture.inc"
#include "native-ocr-languages-runtime-fixture.inc"
#include "native-clipboard-text-runtime-fixture.inc"
#include "native-toast-runtime-fixture.inc"
#include "native-keyboard-notification-runtime-fixture.inc"
#include "native-clipboard-image-runtime-fixture.inc"
#include "native-alert-runtime-fixture.inc"
#include "native-dialog-runtime-fixture.inc"
static void checkGesture(bool (*handler)(UInt8 *, NSError **), NSString *payload, int fingerCount, int cancelAfter) {
    injected.clear(); touchToken = [TLinkCancellationToken new]; cancelAt = cancelAfter;
    auto context = parent(); context.cancellationToken = touchToken;
    auto call = TLinkNativeCallContext(context, NO, NO);
    TLinkNativeBudgetScope scope([call nativeBudget]);
    NSError *error = nil;
    assert(!handler((UInt8 *)payload.UTF8String, &error) && error);
    assert([error.localizedDescription containsString:@"AbortError"]);
    assert(injected.size() >= size_t(fingerCount * 2));
    for (int i = 0; i < fingerCount; ++i) {
        assert(injected[size_t(i)].type == TOUCH_DOWN);
        assert(injected[injected.size() - size_t(i) - 1].type == TOUCH_UP);
    }
    const auto count = injected.size();
    assert(!handler((UInt8 *)payload.UTF8String, &error) && injected.size() == count);
}
static void timingCases() {
    fakeTiming = true;
    const auto run = [](bool (*handler)(UInt8 *, NSError **), const char *payload, uint64_t work = 7000000) {
        injected.clear();frameTimes.clear();touchToken = nil;cancelAt = 0;
        fakeNow = 1000000;frameWork = work;oversleep = 2000000;fakeWaits = 0;
        TLinkNativeBudgetScope scope([TLinkNativeCallContext(parent(), NO, NO) nativeBudget]);
        NSError *error = nil;assert(handler((UInt8 *)payload, &error) && !error);
    };
    run(zx_handleNativeTap, "20;;30;;100;;19");
    assert(frameTimes.size() == 2 && frameTimes[0] == 1000000 && frameTimes[1] == 103000000);
    run(zx_handleNativeSwipe, "20;;30;;80;;90;;100;;19;;10");
    assert(frameTimes.size() == 11 && frameTimes[0] == 1000000);
    for (unsigned i = 1; i <= 10; ++i) assert(frameTimes[i] == 3000000 + uint64_t(i) * 10000000);
    assert(injected.back().type == TOUCH_UP && injected.back().x == 80 && injected.back().y == 90);
    run(zx_handleNativeGesture, "19;;90;;20,30|40,50|60,70|80,90");
    assert(frameTimes.size() == 5 && frameTimes[0] == 1000000 && frameTimes[1] == 33000000 && frameTimes[2] == 63000000 &&
        frameTimes[3] == 93000000 && frameTimes[4] == 100000000);
    run(zx_handleNativeGesture, "zoom;;250;;500;;20;;80;;90;;3;;4");
    assert(frameTimes.size() == 5 && frameTimes[1] == 33000000 && frameTimes[2] == 63000000 && frameTimes[3] == 93000000 && frameTimes[4] == 100000000);
    assert(injected.size() == 15); // all three fingers in DOWN, three MOVEs and UP
    run(zx_handleNativeSwipe, "20;;30;;80;;90;;100;;19;;10", 40000000);
    assert(fakeWaits == 0 && frameTimes.size() == 11);
    for (unsigned i = 0; i <= 10; ++i) assert(frameTimes[i] == 1000000 + uint64_t(i) * 40000000);
    // Last-point cancellation must still return failure and issue owned UP.
    checkGesture(zx_handleNativeGesture, @"19;;0;;20,30|40,50", 1, 2);
    checkGesture(zx_handleNativeGesture, @"zoom;;250;;500;;20;;80;;50;;2;;2", 2, 4);
    fakeTiming = false;touchToken = nil;cancelAt = 0;injected.clear();
    // Concrete old fixed-point boundaries, including finite clamping.
    zx_performSingleTouch(TOUCH_DOWN, 19, -1, 0.95);
    assert(injected.back().index == 19 && injected.back().x == 0 && injected.back().y == 1);
    zx_performSingleTouch(TOUCH_UP, 19, 1e30, 9999.89);
    assert(injected.back().x == 9999 && injected.back().y == 9999);
    puts("Actual gesture timing passed: typed frames, consumed DOWN/work/oversleep, scheduled final point, ordered overdue frames, exact endpoint and final-frame cancellation cleanup.");
}
static void typedTouchCases(TLinkInProcessNativeBridge *bridge) {
    const int wireCalls=calls;
    const auto resetTouch=[](TLinkTaskExecutionContext *context){
        injected.clear();frameTimes.clear();fakeNow=1000000;frameWork=7000000;oversleep=2000000;fakeWaits=0;
        touchToken=context.cancellationToken;cancelAt=0;throwAt=0;licenseAllowed=true;stopInLicense=false;
    };
    const auto invoke=[bridge](NSString *method,NSArray *args,TLinkTaskExecutionContext *context)->NSDictionary *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:method arguments:args];
        auto response=[bridge executeRequest:request context:context error:nil];
        assert(response.ok && !TLinkCurrentNativeBudget());return response.value;
    };
    fakeTiming=true;
    // Compare actual new bridge branches with the old NSString encoder plus
    // actual RAW adapter/executor, including rounding and floatValue boundaries.
    for(unsigned trial=0;trial<160;++trial){
        const double x=trial<8?std::vector<double>{-1e308,-0.005,0.945,0.95,1.005,9999.89,1e30,1e308}[trial]:double(trial)*123.4567-500;
        const double y=double(trial)*0.00495+0.945;
        const bool swipe=trial%3==1,longPress=trial%3==2;
        NSString *method=swipe?TLinkJSNativeMethodSwipe:(longPress?TLinkJSNativeMethodLongPress:TLinkJSNativeMethodTap);
        const double duration=double(trial%17)+0.5;
        NSArray *args=swipe?@[@(x),@(y),@75.125,@87.955,@(duration)]:(longPress?@[@(x),@(y),@(duration)]:@[@(x),@(y)]);
        auto context=parent();resetTouch(context);
        NSDictionary *result=invoke(method,args,context);
        const auto expectedPoints=injected;const auto expectedTimes=frameTimes;
        assert(lastLicenseTask==(swipe?63:62) && licenseBudget->response().empty() && licenseBudget->response().capacity()==0);
        resetTouch(context);NSError *error=nil;
        NSString *wire=swipe?[NSString stringWithFormat:@"%.2f;;%.2f;;%.2f;;%.2f;;%.0f",x,y,75.125,87.955,duration]:
            (longPress?[NSString stringWithFormat:@"%.2f;;%.2f;;%.0f",x,y,duration]:[NSString stringWithFormat:@"%.2f;;%.2f",x,y]);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);
         if(swipe)zx_handleNativeSwipe((UInt8 *)wire.UTF8String,&error);else zx_handleNativeTap((UInt8 *)wire.UTF8String,&error);}
        NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw] && [result[@"ok"] boolValue]==(error==nil));
        assert(expectedPoints.size()==injected.size() && expectedTimes==frameTimes);
        for(size_t j=0;j<injected.size();++j)assert(injected[j].type==expectedPoints[j].type&&injected[j].index==expectedPoints[j].index&&
            injected[j].x==expectedPoints[j].x&&injected[j].y==expectedPoints[j].y);
    }
    const auto zoomState=[](){return std::vector<uint64_t>{
        sTLinkZoomAttemptCount.load(),sTLinkZoomSuccessCount.load(),sTLinkZoomValidationRejectedCount.load(),
        sTLinkZoomDispatchExceptionCount.load(),sTLinkZoomCleanupCount.load(),sTLinkZoomCancelledCount.load(),sTLinkZoomFrameCount.load(),
        uint64_t(sTLinkZoomLastResult.load()),uint64_t(sTLinkZoomLastDirection.load()),uint64_t(sTLinkZoomLastFingerCount.load()),
        uint64_t(sTLinkZoomLastSteps.load()),uint64_t(sTLinkZoomLastDurationMs.load())};};
    const auto parity=[&](NSString *method,NSArray *args,NSString *wire){
        auto context=parent(30);resetTouch(context);const int gatesBefore=licenseCalls;
        const auto before=zoomState();NSDictionary *result=invoke(method,args,context);const auto after=zoomState();
        const auto expectedPoints=injected;const auto expectedTimes=frameTimes;
        if(wire.length+2>8192){failure(result,@"input_too_large");assert(injected.empty()&&licenseCalls==gatesBefore);return;}
        assert(lastLicenseTask==64 && licenseCalls==gatesBefore+1 && licenseBudget->response().capacity()==0);
        resetTouch(context);NSError *error=nil;const auto rawBefore=zoomState();
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);zx_handleNativeGesture((UInt8 *)wire.UTF8String,&error);}
        const auto rawAfter=zoomState();NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw]&&[result[@"ok"] boolValue]==(error==nil));
        assert([result[@"parts"] isEqualToArray:[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert(expectedPoints.size()==injected.size()&&expectedTimes==frameTimes);
        for(size_t j=0;j<injected.size();++j)assert(injected[j].type==expectedPoints[j].type&&injected[j].index==expectedPoints[j].index&&injected[j].x==expectedPoints[j].x&&injected[j].y==expectedPoints[j].y);
        for(size_t j=0;j<after.size();++j)assert(j<7?after[j]-before[j]==rawAfter[j]-rawBefore[j]:after[j]==rawAfter[j]);
    };
    const auto gesture=[&](NSArray *points,NSDictionary *options){
        NSString *encoded=TLinkautoJSEncodeGesturePoints(points);assert(encoded);
        const int finger=TLinkautoJSIntOption(options,@"finger",0);
        int duration=TLinkautoJSIntOption(options,@"duration",TLinkautoJSIntOption(options,@"durationMs",300));
        if(duration<0)duration=0;if(duration>60000)duration=60000;
        NSString *wire=[NSString stringWithFormat:@"%d;;%d;;%@",finger,duration,encoded];
        parity(TLinkJSNativeMethodGesture,@[points,options],wire);
    };
    for(unsigned trial=0;trial<80;++trial){
        NSMutableArray *points=[NSMutableArray array];
        for(unsigned j=0;j<2+trial%9;++j){double x=double(trial)*1.005+double(j)*0.945,y=double(j)*10.005-1;
            [points addObject:j%2?@{@"x":@(x),@"y":@(y)}:@[@(x),@(y)]];}
        gesture(points,@{@"durationMs":@(trial%31),@"finger":@(trial%2?19:0)});
    }
    gesture(@[@{@"y":@20},@[@40.945,@50.005]],@{});
    gesture(@[@[@1e308,@20],@[@30,@40]],@{@"duration":@0});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"finger":@20,@"duration":@0});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"duration":@-10});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"duration":@60001});
    NSMutableArray *many=[NSMutableArray array];for(unsigned j=0;j<512;++j)[many addObject:@[@1234.56,@5678.90]];
    many[0]=@[@0,@0];many[1]=@[@12.56,@5678.90];
    assert(TLinkautoJSEncodeGesturePoints(many).length+9==8192);gesture(many,@{@"finger":@19,@"duration":@0});
    many[1]=@[@123.56,@5678.90];assert(TLinkautoJSEncodeGesturePoints(many).length+9==8193);gesture(many,@{@"finger":@19,@"duration":@0});
    const auto zoom=[&](double x,double y,double first,double last,NSDictionary *options){
        int duration=TLinkautoJSIntOption(options,@"durationMs",300),fingers=TLinkautoJSIntOption(options,@"fingerCount",2),steps=TLinkautoJSIntOption(options,@"steps",20),finger=TLinkautoJSIntOption(options,@"baseFinger",0);
        double angle=TLinkautoJSDoubleOption(options,@"angleDegrees",0.0);
        NSString *wire=[NSString stringWithFormat:@"zoom;;%.2f;;%.2f;;%.2f;;%.2f;;%d;;%d;;%d;;%.2f;;%d",x,y,first,last,duration,fingers,steps,angle,finger];
        parity(TLinkJSNativeMethodZoom,@[@(x),@(y),@(first),@(last),options],wire);
    };
    for(unsigned trial=0;trial<40;++trial)zoom(250.005,500.945,20.125,80.955,@{@"durationMs":@(50+trial*10),@"steps":@(2+trial%9),@"fingerCount":@(2+trial%2),@"angleDegrees":@(double(trial)*7.125-140),@"baseFinger":@(trial%2?17:18)});
    zoom(250,500,20,80,@{});zoom(250,500,80,20,@{@"fingerCount":@3,@"steps":@120,@"durationMs":@5000});
    for(NSDictionary *bad in @[@{@"durationMs":@49},@{@"durationMs":@5001},@{@"fingerCount":@1},@{@"fingerCount":@4},@{@"steps":@1},@{@"steps":@121},@{@"angleDegrees":@361},@{@"angleDegrees":@(NAN)},@{@"angleDegrees":@(INFINITY)},@{@"baseFinger":@-1},@{@"baseFinger":@(INT_MAX)},@{@"baseFinger":@19}])zoom(250,500,20,80,bad);
    zoom(250,500,0,80,@{});zoom(250,500,20,20,@{});zoom(0,500,20,80,@{});
    auto context=parent();resetTouch(context);licenseAllowed=false;

    NSDictionary *result=invoke(TLinkJSNativeMethodTap,@[@20,@30],context);
    assert(![result[@"ok"] boolValue] && [result[@"raw"] isEqualToString:@"-1;;license_required task=62\r\n"] && injected.empty());
    context=parent();resetTouch(context);stopInLicense=true;
    failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"AbortError");assert(injected.empty());
    context=parent();resetTouch(context);[context.cancellationToken cancel];const int gates=licenseCalls;
    failure(invoke(TLinkJSNativeMethodSwipe,@[@20,@30,@80,@90,@500],context),@"AbortError");assert(injected.empty()&&licenseCalls==gates);
    context=parent();resetTouch(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,1024)];
    failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"TimeoutError");assert(injected.empty()&&licenseCalls==gates);
    context=parent();resetTouch(context);cancelAt=1;
    failure(invoke(TLinkJSNativeMethodLongPress,@[@20,@30,@60000],context),@"AbortError");
    assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    for(bool cpp:{false,true}){
        context=parent();resetTouch(context);throwAt=1;throwCpp=cpp;
        failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"native_exception");
        assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    }
    for(NSString *method:@[TLinkJSNativeMethodGesture,TLinkJSNativeMethodZoom]){
        NSArray *args=[method isEqualToString:TLinkJSNativeMethodZoom]?@[@250,@500,@20,@80,@{@"durationMs":@50,@"steps":@2,@"fingerCount":@3}]:@[@[@[@20,@30],@[@40,@50]],@{@"duration":@0,@"finger":@19}];
        context=parent();resetTouch(context);licenseAllowed=false;NSDictionary *denied=invoke(method,args,context);
        assert(![denied[@"ok"] boolValue]&&lastLicenseTask==64&&injected.empty());
        context=parent();resetTouch(context);stopInLicense=true;failure(invoke(method,args,context),@"AbortError");assert(injected.empty());
        context=parent();resetTouch(context);cancelAt=[method isEqualToString:TLinkJSNativeMethodZoom]?3:1;
        failure(invoke(method,args,context),@"AbortError");
        const size_t fingers=[method isEqualToString:TLinkJSNativeMethodZoom]?3:1;
        assert(injected.size()==fingers*2);for(size_t j=0;j<fingers;++j)assert(injected[injected.size()-1-j].type==TOUCH_UP);
        for(bool cpp:{false,true}){context=parent();resetTouch(context);throwAt=int(fingers*2);throwCpp=cpp;
            NSDictionary *thrown=invoke(method,args,context);assert(![thrown[@"ok"] boolValue]);
            if(!cpp&&fingers==3)assert([thrown[@"raw"] containsString:@"zoom_dispatch_exception"]);else failure(thrown,@"native_exception");
            assert(injected.size()==fingers*3);for(size_t j=0;j<fingers;++j)assert(injected[injected.size()-1-j].type==TOUCH_UP);
        }
    }
    context=parent();resetTouch(context);const int noGate=licenseCalls;
    auto malformed=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodGesture arguments:@[@[@[@1]],@{}]];
    assert(![bridge executeRequest:malformed context:context error:nil].ok&&injected.empty()&&licenseCalls==noGate);
    context=parent(1,3);resetTouch(context);assert([invoke(TLinkJSNativeMethodTap,@[@20,@30],context)[@"ok"] boolValue]);
    context=parent(1,2);resetTouch(context);failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"response_too_large");
    assert(injected.size()==2&&injected.back().type==TOUCH_UP);
    context=parent();resetTouch(context);TLinkNativeTouchRequest invalid;invalid.finger=20;
    result=TLinkExecuteNativeTouch(invalid,context);assert(![result[@"ok"] boolValue]&&injected.empty());
    invalid.kind=static_cast<TLinkNativeTouchKind>(9);const int previous=licenseCalls;
    failure(TLinkExecuteNativeTouch(invalid,context),@"invalid_touch_request");assert(injected.empty()&&licenseCalls==previous);
    fakeTiming=false;context=parent(0.01);resetTouch(context);
    failure(invoke(TLinkJSNativeMethodLongPress,@[@20,@30,@60000],context),@"TimeoutError");
    assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    assert(calls==wireCalls && !TLinkCurrentNativeBudget());licenseBudget.reset();touchToken=nil;cancelAt=0;
    puts("Typed touch actual bridge/entry passed: 160 legacy-wire/frame/timestamp cases, typed gesture/zoom wire/frame/timestamp/diagnostic parity, 8192/8193-byte ingress, task 62/63/64 gates, gate-time cancellation, pre-expiry, output caps, NS/C++ exceptions, owned UP, no raw dispatch or response-buffer allocation.");
}
// Frozen pre-C02b3 object encoder plus the production RAW task-65 executor.
static NSString *legacyBatchWire(NSArray *commands){
    NSMutableArray *wire=[NSMutableArray array];
    for(NSDictionary *cmd in commands){
        NSString *type=[cmd[@"type"] lowercaseString];
        if([type isEqualToString:@"tap"])[wire addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f",
            [cmd[@"x"] doubleValue],[cmd[@"y"] doubleValue],cmd[@"duration"]?[cmd[@"duration"] doubleValue]:50.0]];
        else if([type isEqualToString:@"swipe"])[wire addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f",
            [cmd[@"x1"] doubleValue],[cmd[@"y1"] doubleValue],[cmd[@"x2"] doubleValue],[cmd[@"y2"] doubleValue],cmd[@"duration"]?[cmd[@"duration"] doubleValue]:300.0]];
        else {
            int duration=cmd[@"duration"]?[cmd[@"duration"] intValue]:(cmd[@"durationMs"]?[cmd[@"durationMs"] intValue]:300);
            duration=MAX(0,MIN(60000,duration));
            [wire addObject:[NSString stringWithFormat:@"64%d;;%d;;%@",cmd[@"finger"]?[cmd[@"finger"] intValue]:0,duration,TLinkautoJSEncodeGesturePoints(cmd[@"points"])]];
        }
    }
    return [wire componentsJoinedByString:@"||"];
}
static void typedBatchCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){
        injected.clear();frameTimes.clear();fakeNow=1000000;frameWork=7000000;oversleep=2000000;fakeWaits=0;
        touchToken=context.cancellationToken;cancelAt=0;throwAt=0;licenseAllowed=true;stopInLicense=false;
    };
    const auto invoke=[bridge](NSArray *commands,TLinkTaskExecutionContext *context){
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodBatch arguments:@[commands]];
        auto response=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return response;
    };
    const auto parity=[&](NSArray *commands,NSUInteger exactBytes=0){
        auto context=parent(30);reset(context);const int rawBefore=calls,gates=licenseCalls;
        auto response=invoke(commands,context);assert(response.ok&&calls==rawBefore);
        NSDictionary *result=response.value;NSString *wire=legacyBatchWire(commands);
        if(exactBytes)assert(wire.length+2==exactBytes);
        if(wire.length+2>8192){failure(result,@"input_too_large");assert(licenseCalls==gates&&injected.empty());return;}
        assert(licenseCalls==gates+1&&lastLicenseTask==65&&licenseBudget->response().capacity()==0);
        const auto points=injected;const auto times=frameTimes;
        reset(context);NSError *error=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);zx_handleNativeBatch((UInt8 *)wire.UTF8String,&error);}
        NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw]&&[result[@"ok"] boolValue]==(error==nil));
        assert([result[@"parts"] isEqualToArray:[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert(points.size()==injected.size()&&times==frameTimes);
        for(size_t i=0;i<points.size();++i)assert(points[i].type==injected[i].type&&points[i].index==injected[i].index&&points[i].x==injected[i].x&&points[i].y==injected[i].y);
    };
    fakeTiming=true;
    NSDictionary *tap=@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":@0};
    NSDictionary *swipe=@{@"type":@"swipe",@"x1":@40,@"y1":@50,@"x2":@80,@"y2":@90,@"duration":@16};
    NSDictionary *gesture=@{@"type":@"gesture",@"points":@[@[@20,@30],@[@40,@50]],@"durationMs":@0,@"finger":@19};
    NSArray *normal=@[tap,swipe,gesture,tap];
    for(unsigned trial=0;trial<120;++trial){
        const double x=trial%13?double(trial)*0.945:-1e308;
        parity(@[@{@"type":@"TAP",@"x":@(x),@"y":@(-0.0),@"duration":@(trial?double(trial%17)+0.5:-0.0)},swipe,
            @{@"type":@"gesture",@"points":@[@{},@[@40.945,@50.005]],@"duration":@(int(trial)-60),@"finger":@(trial%21)},tap]);
    }
    parity(@[]);parity(@[@{@"type":@"tap"},@{@"type":@"swipe"}]);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<256;++i)[many addObject:tap];parity(many);
    // Two bounded gesture plans total exactly 8192/8193 legacy characters.
    NSMutableArray *first=[NSMutableArray array],*second=[NSMutableArray array];
    for(unsigned i=0;i<512;++i)[first addObject:@[@0,@0]];
    for(unsigned i=0;i<300;++i)[second addObject:@[@0,@0]];
    for(unsigned extra=0;extra<2;++extra){second[0]=@[@(extra?1e55:1e54),@0];
        parity(@[@{@"type":@"gesture",@"duration":@0,@"points":first},@{@"type":@"gesture",@"duration":@0,@"points":second}],8192+extra);}
    auto context=parent();reset(context);const int gates=licenseCalls,wireCalls=calls;
    // Validate every JS shape before size rejection or the first side effect.
    [many addObject:tap];assert(!invoke(many,context).ok&&injected.empty()&&licenseCalls==gates);
    for(NSArray *bad:@[@[tap,@{@"type":@"unknown"}],@[tap,@{@"type":@"tap",@"x":@(NAN)}],
        @[tap,@{@"type":@"swipe",@"y2":@(INFINITY)}],@[tap,@{@"type":@"gesture",@"points":@[@[]]}],
        @[@{@"type":@"gesture",@"points":first},@{@"type":@"gesture",@"points":first},@{@"type":@"unknown"}]]){
        auto response=invoke(bad,context);assert(!response.ok&&injected.empty()&&licenseCalls==gates&&calls==wireCalls);
    }
    context=parent();reset(context);licenseAllowed=false;
    NSDictionary *result=invoke(normal,context).value;
    assert([result[@"raw"] isEqualToString:@"-1;;license_required task=65\r\n"]&&injected.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(normal,context).value,@"AbortError");assert(injected.empty());
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(normal,context).value,@"AbortError");assert(injected.empty()&&licenseCalls==noGate);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,1024)];
    failure(invoke(normal,context).value,@"TimeoutError");assert(injected.empty()&&licenseCalls==noGate);
    // Cancellation/throws on the second command never start the third, and UP
    // for the active command precedes return. Also cancel between commands.
    for(int boundary:{2,3}){context=parent();reset(context);cancelAt=boundary;
        failure(invoke(normal,context).value,@"AbortError");assert(injected.size()==size_t(boundary==2?2:4)&&injected.back().type==TOUCH_UP);}
    for(bool cpp:{false,true}){context=parent();reset(context);throwAt=3;throwCpp=cpp;
        failure(invoke(normal,context).value,@"native_exception");assert(injected.size()==4&&injected.back().type==TOUCH_UP);}
    context=parent(1,3);reset(context);assert([invoke(normal,context).value[@"ok"] boolValue]);
    context=parent(1,2);reset(context);failure(invoke(normal,context).value,@"response_too_large");assert(injected.back().type==TOUCH_UP);
    context=parent();reset(context);std::vector<TLinkNativeTouchRequest> invalid(257);
    const int beforeInvalid=licenseCalls;failure(TLinkExecuteNativeTouchBatch(invalid,context),@"invalid_touch_request");
    invalid.resize(1);invalid[0].kind=TLinkNativeTouchKind::Zoom;failure(TLinkExecuteNativeTouchBatch(invalid,context),@"invalid_touch_request");assert(licenseCalls==beforeInvalid&&injected.empty());
    fakeTiming=false;context=parent(0.05);reset(context);
    failure(invoke(@[tap,@{@"type":@"swipe",@"duration":@60000},tap],context).value,@"TimeoutError");
    assert(injected.size()==4&&injected.back().type==TOUCH_UP);fakeTiming=true;
    // RAW/mixed, string/negative/extreme duration and embedded-NUL compatibility.
    mode=@"batchRuntime";
    for(id duration:@[@-1,@60001,@(1e100),@"16"]){context=parent();reset(context);const int before=calls;
        NSArray *commands=@[@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":duration}];
        NSString *expected=[@"65" stringByAppendingString:legacyBatchWire(commands)];
        TLinkJSNativeResponse *result=invoke(commands,context);
        assert(result.ok);assert(calls==before+1);
        assert(lastPayload==expected.UTF8String);}
    context=parent();reset(context);const int beforeRaw=calls;
    auto fallback=invoke(@[tap,@"62",tap],context);assert(fallback.ok&&![fallback.value[@"ok"] boolValue]&&calls==beforeRaw+1&&injected.size()==2);
    context=parent();reset(context);unichar zero=0;NSString *nul=[@"62" stringByAppendingString:[NSString stringWithCharacters:&zero length:1]];
    const int beforeNul=calls;failure(invoke(@[tap,nul],context).value,@"invalid_payload");assert(injected.empty()&&calls==beforeNul);
    context=parent();reset(context);const int beforeDelimiter=calls;
    assert(!invoke(@[tap,@"62||62"],context).ok&&calls==beforeDelimiter&&injected.empty());
    mode=@"echo";fakeTiming=false;cancelAt=0;throwAt=0;touchToken=nil;licenseBudget.reset();
    puts("Typed batch actual bridge/entry passed: legacy task-65 frame/timestamp/reply parity, 256 commands, exact 8192/8193 ingress, full JS prevalidation, one license gate, first failure, cancellation/exception UP, output cap and RAW compatibility.");
}
static void typedColorCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorFault=0;cancelColor=false;colorError=nil;
    };
    const auto invoke=[bridge](double x,double y,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodPickColor arguments:@[@(x),@(y)]];
        TLinkJSNativeResponse *result=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const int rawBefore=calls;
    for(unsigned i=0;i<200;++i){
        const double x=i<12?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2.5,8191.49,8191.5,8192,2147483648.0,1e308}[i]:double(i)*47.125-8.5;
        const double y=double(i)*0.5;auto context=parent(30);reset(context);const int gates=licenseCalls;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *response=invoke(x,y,context);assert(response.ok);
        NSDictionary *result=response.value;assert(licenseCalls==gates+1&&lastLicenseTask==23&&colorBudget->response().capacity()==0);
        const uint64_t after=TLinkNativeNowNs();
        assert(colorBudget==licenseBudget&&colorBudget->deadline()>=before+3000000000ULL&&colorBudget->deadline()<=after+3000000000ULL);
        NSString *wire=[NSString stringWithFormat:@"%.0f;;%.0f",x,y];NSArray *parts=[wire componentsSeparatedByString:@";;"];int px=0,py=0;
        if(!TLinkColorInt([parts[0] UTF8String],px)||!TLinkColorInt([parts[1] UTF8String],py)||px<0||py<0||px>=8192||py>=8192){
            assert([result[@"raw"] isEqualToString:@"-1;;color_parameters_invalid\r\n"]);continue;
        }
        NSString *expected=[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n",px%256,py%256,(px+py)%256];
        assert([result[@"ok"] boolValue]&&[result[@"raw"] isEqualToString:expected]);
        assert([result[@"parts"] isEqualToArray:[[expected stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert([result[@"red"] intValue]==px%256&&[result[@"green"] intValue]==py%256&&[result[@"blue"] intValue]==(px+py)%256);
    }
    auto context=parent();reset(context);const int noRead=colorCalls;
    licenseAllowed=false;NSDictionary *denied=invoke(0,0,context).value;
    assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=23\r\n"]&&colorCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(0,0,context).value,@"AbortError");assert(colorCalls==noRead);
    // A local C01 expiry keeps the caller live and retains the RAW task error.
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);
    [context setNativeBudget:caller];const uint64_t callerDeadline=caller->deadline();
    NSDictionary *expired=invoke(0,0,context).value;
    assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorCalls==noRead);
    assert(!caller->stopped()&&caller->deadline()==callerDeadline&&caller->response().capacity()==0);

    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(0,0,context).value,@"AbortError");assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(0,0,context).value,@"TimeoutError");assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent();reset(context);assert(!invoke(NAN,0,context).ok&&!invoke(0,INFINITY,context).ok);assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent(0.25);reset(context);assert([invoke(0,0,context).value[@"ok"] boolValue]);assert(colorBudget->remainingSeconds(3)<0.3);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_memory_budget",@"color_cancelled_or_timed_out"]){
        context=parent();reset(context);colorError=code;NSDictionary *error=invoke(0,0,context).value;
        NSString *expected=[NSString stringWithFormat:@"-1;;%@\r\n",code];
        assert([error[@"raw"] isEqualToString:expected]&&![error[@"ok"] boolValue]);
    }
    context=parent();reset(context);cancelColor=true;failure(invoke(0,0,context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorFault=fault;failure(invoke(0,0,context).value,@"native_exception");}
    context=parent(1,12);reset(context);assert([invoke(0,0,context).value[@"ok"] boolValue]);
    context=parent(1,11);reset(context);failure(invoke(0,0,context).value,@"response_too_large");
    assert(calls==rawBefore&&!TLinkCurrentNativeBudget());colorBudget.reset();licenseBudget.reset();touchToken=nil;
    puts("Typed color actual bridge/entry passed: 200 legacy decimal/reply/parts/RGB cases, task-23 authority, C01/parent deadline scope, invalid preflight, stop/fault/output bounds and no raw dispatch or response vector.");
}
static void typedColorRangeCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorRangeFault=0;colorRangeError=nil;cancelRange=false;};
    const auto request=[](NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFindColor arguments:@[options]];};
    const auto invoke=[bridge,request](NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,reset,request,invoke](NSDictionary *options,NSString *backendError){
        mode=@"colorRangeRuntime";auto oldContext=parent(30);reset(oldContext);colorRangeError=backendError;const int beforeOld=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyColorRange:request(options) context:oldContext];const int dispatched=calls-beforeOld;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);colorRangeError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=colorRangeCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"live range parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&colorRangeCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==28&&colorRangeBudget==licenseBudget&&!colorRangeBudget->capturesResponse()&&colorRangeBudget->response().capacity()==0);
            assert(colorRangeBudget->deadline()>=started+3000000000ULL&&colorRangeBudget->deadline()<=ended+3000000000ULL);}
    };
    for(unsigned i=0;i<200;++i){
        const double x=i<12?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.49,7.5,8191.5,double(INT_MAX),1e308}[i]:double(int(i%23)-4)*0.5;
        const double width=std::vector<double>{double(INT_MIN),-1.5,-0.0,0.5,2.5,double(INT_MAX),1e308}[i%7];
        compare(@{@"x":@(x),@"y":@(double(i%8)*0.5),@"width":@(width),@"height":@(double(int(i%5)-2)*0.5),@"redMin":@(i%3?0:11),@"skip":@(i%5?int(i%4):INT_MAX)},nil);
    }
    NSDictionary *hit=@{},*miss=@{@"redMin":@11};compare(hit,nil);compare(miss,nil);
    for(NSDictionary *options:@[@{@"x":@(NAN)},@{@"y":@(INFINITY)},@{@"width":@(-INFINITY)},@{@"height":@(NAN)},@{@"x":@8192},@{@"x":@8},@{@"skip":@-1},@{@"skip":@(INT_MAX)},@{@"redMin":@-1},@{@"redMax":@256},@{@"greenMin":@20,@"greenMax":@19},@{@"blueMin":@31},@{@"x":@"1.5",@"width":@"2.5"},@{@"x":[NSNull null],@"redMin":[NSNull null]},@{@"x":@(-0.0),@"width":@(INT_MIN),@"height":@(INT_MAX)}])compare(options,nil);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_source_pixel_limit",@"color_memory_budget",@"color_allocation_failed",@"color_crop_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out"])compare(hit,code);
    compare(@{@"x":@-1},@"color_compute_busy");
    const int wireCalls=calls;auto context=parent();reset(context);const unsigned noRead=colorRangeCalls;licenseAllowed=false;
    NSDictionary *denied=invoke(hit,context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=28\r\n"]&&colorRangeCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(hit,context).value,@"AbortError");assert(colorRangeCalls==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(hit,context).value,@"AbortError");assert(licenseCalls==gates&&colorRangeCalls==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(hit,context).value,@"TimeoutError");assert(licenseCalls==gates&&colorRangeCalls==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];const uint64_t deadline=caller->deadline();
    NSDictionary *expired=invoke(hit,context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorRangeCalls==noRead&&!caller->stopped()&&caller->deadline()==deadline);
    context=parent(0.25);reset(context);assert([invoke(hit,context).value[@"ok"] boolValue]&&colorRangeBudget->remainingSeconds(3)<0.3);
    context=parent();reset(context);cancelRange=true;failure(invoke(hit,context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorRangeFault=fault;failure(invoke(hit,context).value,@"native_exception");}
    for(NSDictionary *options:@[hit,miss]){
        context=parent();reset(context);NSDictionary *success=invoke(options,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(options,context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(options,context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());colorRangeBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed live range actual bridge/entry passed: 200 frozen JS/RAW ROI/RGB/skip cases, finite/default/overflow rules, one task-28 gate, C01/caller isolation, faults/cancel/output bounds and no typed RAW dispatch/response vector.");
}
static void typedLiveColorsCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorPointsFault=0;colorPointsError=nil;cancelColorPoints=false;};
    const auto request=[](NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodIsColors arguments:@[points,options]];};
    const auto invoke=[bridge,request](NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"colorPointsRuntime";auto oldContext=parent(30);reset(oldContext);colorPointsError=backendError;const int beforeOld=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyLiveColors:request(points,options) context:oldContext];const int dispatched=calls-beforeOld;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);colorPointsError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=colorPointsCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(points,options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"live points parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&colorPointsCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==28&&colorPointsBudget==licenseBudget&&!colorPointsBudget->capturesResponse()&&colorPointsBudget->response().capacity()==0);
            assert(colorPointsBudget->deadline()>=started+3000000000ULL&&colorPointsBudget->deadline()<=ended+3000000000ULL);}
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<11?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.5,8191.5,double(INT_MAX),1e308}[i]:double(int(i%23)-4)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(@[@{@"x":@(x),@"y":@1.5,@"r":@10,@"g":@20,@"b":@30},@{@"red":@10,@"green":@20,@"blue":@30}],@{@"mode":@(modeValue),@"value":@(threshold)},nil);
    }
    NSArray *hit=@[@{@"red":@10,@"green":@20,@"blue":@30}],*miss=@[@{}],*badTable=@[@{},@{@"red":@999}];
    compare(hit,@{},nil);compare(miss,@{},nil);compare(badTable,@{},nil);
    compare(@[@{@"red":@11,@"r":@10,@"green":@20,@"blue":@30}],@{},nil);compare(@[@{@"red":[NSNull null],@"r":@10,@"g":@20,@"b":@30}],@{},nil);
    compare(@[@{@"x":@"1.5",@"y":@"2.5",@"r":@"10",@"g":@20,@"b":@30}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(bad,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(many,@{},nil);[many addObject:@{}];compare(many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(many,@{},nil);[many addObject:@[]];compare(many,@{},nil);
    for(unsigned extra=0;extra<2;++extra){
        [many removeAllObjects];for(unsigned i=0;i<512;++i)[many addObject:@{@"x":@(i<3?2e307:(i==3?(extra?2e89:2e88):0))}];
        NSString *wire=[NSString stringWithFormat:@"282;;%@;;1;;0.0000",TLinkautoJSEncodePointColorTable(many)];assert(wire.length==8192+extra);compare(many,@{},nil);
    }
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"value":[NSNull null],@"tolerance":@1}])compare(hit,options,nil);
    compare(badTable,@{@"mode":@2},nil);compare(@[@{},@{@"x":@8}],@{},nil);compare(@[@{@"x":@8192}],@{},nil);
    compare(@[@{@"x":@-1},@{@"red":@999}],@{},nil);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_source_pixel_limit",@"color_memory_budget",@"color_allocation_failed",@"color_crop_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out"])compare(hit,@{},code);
    compare(badTable,@{},@"color_compute_busy");compare(@[@{@"x":@8192}],@{},@"color_capture_failed");compare(@[@{@"x":@8}],@{},@"color_capture_failed");
    const int wireCalls=calls;auto context=parent();reset(context);licenseAllowed=false;const unsigned noRead=colorPointsCalls;
    NSDictionary *denied=invoke(hit,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=28\r\n"]&&colorPointsCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(hit,@{},context).value,@"AbortError");assert(colorPointsCalls==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(hit,@{},context).value,@"AbortError");assert(licenseCalls==gates&&colorPointsCalls==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(hit,@{},context).value,@"TimeoutError");assert(licenseCalls==gates&&colorPointsCalls==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];const uint64_t deadline=caller->deadline();
    NSDictionary *expired=invoke(hit,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorPointsCalls==noRead&&!caller->stopped()&&caller->deadline()==deadline);
    context=parent(0.25);reset(context);assert([invoke(hit,@{},context).value[@"ok"] boolValue]&&colorPointsBudget->remainingSeconds(3)<0.3);
    context=parent();reset(context);cancelColorPoints=true;failure(invoke(hit,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorPointsFault=fault;failure(invoke(hit,@{},context).value,@"native_exception");}
    for(NSArray *list:@[hit,miss]){context=parent();reset(context);NSDictionary *success=invoke(list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(list,@{},context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(list,@{},context).value,@"response_too_large");}
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());colorPointsBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed live points actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/defaults/full table and pre/post-capture bounds, 512/513 and exact ingress, scalar modes, one task-28 gate, C01/caller/fault/output bounds and no typed RAW dispatch/response vector.");
}
static void typedLiveMultiCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorMultiFault=0;colorMultiError=nil;cancelColorMulti=false;};
    const auto request=[](NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFindMultiColor arguments:@[points,options]];};
    const auto invoke=[bridge,request](NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"colorMultiRuntime";auto oldContext=parent(30);reset(oldContext);colorMultiError=backendError;const int beforeOld=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyLiveMulti:request(points,options) context:oldContext];const int dispatched=calls-beforeOld;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);colorMultiError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=colorMultiCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(points,options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"live multi parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&colorMultiCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==28&&colorMultiBudget==licenseBudget&&!colorMultiBudget->capturesResponse()&&colorMultiBudget->response().capacity()==0);
            assert(colorMultiBudget->deadline()>=started+3000000000ULL&&colorMultiBudget->deadline()<=ended+3000000000ULL);}
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<11?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.5,8191.5,double(INT_MAX),1e308}[i]:double(int(i%23)-4)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(@[@{@"x":@(x),@"y":@1.5,@"r":@10,@"g":@20,@"b":@30},@{@"red":@10,@"green":@20,@"blue":@30}],@{@"mode":@(modeValue),@"value":@(threshold),@"x":@(double(int(i%17)-4)*0.5),@"width":@(double(int(i%9)-2)*0.5),@"height":@(-0.0),@"skip":@(i%11?int(i%4):INT_MAX)},nil);
    }
    NSArray *hit=@[@{@"red":@10,@"green":@20,@"blue":@30}],*miss=@[@{}],*badTable=@[@{},@{@"red":@999}];
    compare(hit,@{},nil);compare(miss,@{},nil);compare(badTable,@{},nil);
    compare(@[@{@"red":@11,@"r":@10,@"green":@20,@"blue":@30}],@{},nil);compare(@[@{@"red":[NSNull null],@"r":@10,@"g":@20,@"b":@30}],@{},nil);
    compare(@[@{@"x":@"1.5",@"y":@"2.5",@"r":@"10",@"g":@20,@"b":@30}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(bad,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(many,@{},nil);[many addObject:@{}];compare(many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(many,@{},nil);[many addObject:@[]];compare(many,@{},nil);
    for(unsigned extra=0;extra<2;++extra){
        [many removeAllObjects];for(unsigned i=0;i<512;++i)[many addObject:@{@"x":@(i<3?2e307:(i==3?(extra?2e74:2e73):0))}];
        NSString *wire=[NSString stringWithFormat:@"283;;0;;0;;0;;0;;%@;;1;;0.0000;;0",TLinkautoJSEncodePointColorTable(many)];assert(wire.length==8192+extra);compare(many,@{},nil);
    }
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"value":[NSNull null],@"tolerance":@1}])compare(hit,options,nil);
    compare(badTable,@{@"mode":@2},nil);compare(@[@{},@{@"x":@8}],@{},nil);compare(@[@{@"x":@8192}],@{},nil);
    compare(@[@{@"x":@-1},@{@"red":@999}],@{},nil);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_source_pixel_limit",@"color_memory_budget",@"color_allocation_failed",@"color_crop_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out"])compare(hit,@{},code);
    compare(badTable,@{},@"color_compute_busy");compare(@[@{@"x":@8192}],@{},@"color_capture_failed");compare(@[@{@"x":@8}],@{},@"color_capture_failed");
    for(NSDictionary *options:@[@{@"x":@(NAN)},@{@"height":@(INFINITY)},@{@"width":@(1e308)},@{@"x":@(INT_MIN),@"y":@(INT_MAX),@"width":@(INT_MIN),@"height":@(INT_MAX)},@{@"skip":@-1},@{@"skip":@(INT_MAX)},@{@"x":@"1.5",@"width":@"2.5"}])compare(hit,options,nil);
    compare(@[@{@"x":@-1,@"y":@-1,@"red":@10,@"green":@20,@"blue":@30}],@{},nil);
    compare(@[@{@"x":@(INT_MIN)},@{@"x":@(INT_MAX)}],@{},nil);compare(badTable,@{@"width":@(1e308)},nil);
    const int wireCalls=calls;auto context=parent();reset(context);licenseAllowed=false;const unsigned noRead=colorMultiCalls;
    NSDictionary *denied=invoke(hit,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=28\r\n"]&&colorMultiCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(hit,@{},context).value,@"AbortError");assert(colorMultiCalls==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(hit,@{},context).value,@"AbortError");assert(licenseCalls==gates&&colorMultiCalls==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(hit,@{},context).value,@"TimeoutError");assert(licenseCalls==gates&&colorMultiCalls==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];const uint64_t deadline=caller->deadline();
    NSDictionary *expired=invoke(hit,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorMultiCalls==noRead&&!caller->stopped()&&caller->deadline()==deadline);
    context=parent(0.25);reset(context);assert([invoke(hit,@{},context).value[@"ok"] boolValue]&&colorMultiBudget->remainingSeconds(3)<0.3);
    context=parent();reset(context);cancelColorMulti=true;failure(invoke(hit,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorMultiFault=fault;failure(invoke(hit,@{},context).value,@"native_exception");}
    for(NSArray *list:@[hit,miss]){context=parent();reset(context);NSDictionary *success=invoke(list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(list,@{},context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(list,@{},context).value,@"response_too_large");}
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());colorMultiBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed live multi actual bridge/entry passed: 160 frozen JS/RAW ROI/offset/skip cases, aliases/full-table/signed extents, INT_MIN offsets/INT_MAX skip, 512/513/exact ingress, scalar modes, one task-28 gate, C01/caller/fault/output and no typed RAW dispatch/response vector.");
}
static void typedFrameImageCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameImageFault=0;frameImageError=nil;cancelFrameImage=false;};
    const auto request=[](int fid,int iid,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFindImageInFrame arguments:@[@(fid),@(iid),options]];};
    const auto invoke=[bridge,request](int fid,int iid,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{TLinkJSNativeResponse *result=[bridge executeRequest:request(fid,iid,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;};
    const auto compare=[bridge,request,invoke,reset](int fid,int iid,NSDictionary *options,NSString *backendError){
        mode=@"frameImageRuntime";auto oldContext=parent(30);reset(oldContext);frameImageError=backendError;const int oldCalls=calls;TLinkJSNativeResponse *legacy=[bridge legacyFrameImage:request(fid,iid,options) context:oldContext];const int dispatched=calls-oldCalls;
        auto context=parent(30);reset(context);frameImageError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=frameImageCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(fid,iid,options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame image parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&frameImageCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==68&&frameImageBudget==licenseBudget&&frameImageBudget->response().capacity()==0&&!frameImageBudget->capturesResponse());assert(frameImageBudget->deadline()>=started+8000000000ULL&&frameImageBudget->deadline()<=ended+8000000000ULL);}
    };
    for(unsigned n=0;n<120;++n){const double x=n<10?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),1e308,double(NAN)}[n]:double(int(n%19)-4)*.5;
        compare(1,2,@{@"x":@(x),@"width":@(double(int(n%9)-2)*.5),@"acceptable":@(n%2?.5:.95004),@"scaleMin":@(n%3?1:.01004),@"scaleMax":@(n%5?1:16.00004),@"scaleStep":@(n%7?.25:.00004),@"coord":n%2?@"point":@"pixel",@"pixelSkip":@(n%1025)},nil);}
    NSDictionary *hit=@{@"acceptable":@0.5},*miss=@{};compare(1,2,hit,nil);compare(1,2,miss,nil);compare(0,2,hit,nil);compare(1,0,hit,nil);
    for(NSDictionary *options:@[@{@"x":@(INFINITY)},@{@"width":@(NAN)},@{@"acceptable":@(NAN)},@{@"acceptable":@1.00006},@{@"scaleMin":@16.00006},@{@"scaleMax":@(INFINITY)},@{@"scaleStep":@0},@{@"pixelSkip":@1024},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@-1},@{@"coord":@"pixel;;x"},@{@"coord":@"PoInT"},@{@"x":@"1.5",@"acceptable":@"0.5"}])compare(1,2,options,nil);
    unichar nul=0,high=0xd800;NSString *nullString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nullString,[NSString stringWithCharacters:&high length:1],@"điểm",@"",@"pixel\r"] )compare(1,2,@{@"coord":coord},nil);
    NSString *emptyWire=@"681;;2;;0;;0;;0;;0;;0.9500;;1.0000;;1.0000;;1.0000;;0;;;;1000";const NSUInteger limit=8192-emptyWire.length;
    for(unsigned extra=0;extra<2;++extra){compare(1,2,@{@"coord":[@"x" stringByPaddingToLength:limit+extra withString:@"x" startingAtIndex:0]},nil);compare(1,2,@{@"coord":[nullString stringByPaddingToLength:limit+extra withString:@"x" startingAtIndex:0]},nil);}
    for(NSString *code:@[@"frame_not_found",@"frame_missing_gray",@"frame_expired",@"image_not_found",@"frame_geometry_invalid",@"frame_coordinate_invalid",@"image_compute_busy",@"image_scratch_budget",@"template_work_limit"])compare(1,2,hit,code);
    const int wireCalls=calls;auto context=parent();reset(context);licenseAllowed=false;const unsigned reads=frameImageCalls;NSDictionary *denied=invoke(1,2,hit,context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=68\r\n"]&&frameImageCalls==reads);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,2,hit,context).value,@"AbortError");assert(frameImageCalls==reads);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(1,2,hit,context).value,@"AbortError");assert(licenseCalls==gates&&frameImageCalls==reads);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(1,2,hit,context).value,@"TimeoutError");assert(licenseCalls==gates);
    context=parent(30);reset(context);licenseDelayMs=8100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];NSDictionary *expired=invoke(1,2,hit,context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameImageCalls==reads);
    context=parent();reset(context);cancelFrameImage=true;failure(invoke(1,2,hit,context).value,@"AbortError");for(int fault:{1,2}){context=parent();reset(context);frameImageFault=fault;failure(invoke(1,2,hit,context).value,@"native_exception");}
    for(NSDictionary *options:@[hit,miss]){context=parent();reset(context);NSDictionary *success=invoke(1,2,options,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];context=parent(1,bytes);reset(context);assert([invoke(1,2,options,context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(1,2,options,context).value,@"response_too_large");}
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameImageBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame image bridge/entry passed: 120 frozen JS/RAW cases, exact fields/rounding/ingress/encoding, one task-68 gate, eight-second C01/caller isolation, denial/cancel/fault/output and no typed RAW dispatch.");
}
static void typedImageCaptureCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){mode=@"imageCaptureRuntime";imageCaptureToken=context.cancellationToken;touchToken=imageCaptureToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;imageCaptureFault=0;cancelImageCapture=false;imageCaptureDelay=0;imageCaptureError=nil;hugeImageCaptureReply=false;capturedImages.clear();};
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodCaptureImage arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->NSDictionary *{NSDictionary *value=[bridge executeRequest:request(args) context:context error:nil].value;assert(!TLinkCurrentNativeBudget());return value;};
    const auto make=[](NSArray *owners)->TLinkTaskExecutionContext *{auto context=parent(30);context.ownerSessionId=owners[0];context.ownerRunId=owners[1];context.ownerRuntime=owners[2];return context;};
    const auto compare=[bridge,request,invoke,reset,make](NSArray *args,NSArray *owners,NSString *code){
        auto oldContext=make(owners);reset(oldContext);imageCaptureError=code;const int oldCalls=calls;unsigned oldTracking=trackImages;
        TLinkJSNativeResponse *oldResponse=[bridge legacyImageCapture:request(args) context:oldContext];NSDictionary *old=oldResponse.value;
        const int dispatched=calls-oldCalls;const unsigned tracking=trackImages-oldTracking;auto expected=observedImageCapture;
        auto context=make(owners);reset(context);imageCaptureError=code;oldTracking=trackImages;const int before=calls,gates=licenseCalls;const unsigned opens=imageCaptureCalls;
        const uint64_t start=TLinkNativeNowNs();NSDictionary *typed=invoke(args,context);const uint64_t end=TLinkNativeNowNs();
        if(typed&&![typed isEqual:old])std::fprintf(stderr,"image capture parity: old %s, typed %s\n",[[old description] UTF8String],[[typed description] UTF8String]);
        assert((!old&&!typed)||[typed isEqual:old]);assert(calls==before&&licenseCalls==gates+dispatched&&imageCaptureCalls==opens+dispatched&&trackImages-oldTracking==tracking);
        if(dispatched){assert(observedImageCapture.x==expected.x&&observedImageCapture.y==expected.y&&observedImageCapture.width==expected.width&&observedImageCapture.height==expected.height&&observedImageCapture.sessionId==expected.sessionId&&observedImageCapture.runId==expected.runId&&observedImageCapture.runtime==expected.runtime&&lastLicenseTask==48);
            assert(imageCaptureBudget==licenseBudget&&imageCaptureBudget->response().capacity()==0&&imageCaptureBudget->deadline()>=start+30000000000ULL&&imageCaptureBudget->deadline()<=end+30000000000ULL);}
        if([typed[@"ok"] boolValue])assert(lastTrackedImage==41&&capturedImages.count(41));else assert(capturedImages.empty());
    };
    unichar nul=0,high=0xd800;NSString *nulString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    NSString *emoji=[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0];
    NSArray *tokens=@[@"owner",@"",@";",@"a;;b",@"a\rb\nc",@" js \t",@"Tiếng Việt",nulString,broken,emoji,[@"x" stringByAppendingString:emoji]];
    NSArray *values=@[@0,@(-0.0),@0.49,@0.5,@0.51,@(-.5),@(-.51),@(INT_MAX),@(INT_MIN),@1e100,@(-1e100),@1.7976931348623157e308,@(-1.7976931348623157e308)];
    for(unsigned n=0;n<240;++n)compare(@[values[n%values.count],values[(n/3)%values.count],values[(n/5)%values.count],values[(n/7)%values.count]],@[tokens[n%tokens.count],tokens[(n/3)%tokens.count],tokens[(n/7)%tokens.count]],nil);
    for(NSArray *args in @[@[],@[@1],@[@1,@2],@[@1,@2,@3],@[@(NAN),@0,@1,@1],@[@0,@(INFINITY),@1,@1]])compare(args,@[@"session",@"run",@"test"],nil);
    for(NSString *code:@[@"image_compute_busy",@"Unable to capture screenshot.",@"Failed to crop screenshot.",@"image_pixel_or_memory_limit",@"Failed to convert screenshot to mat.",@"Image object limit reached. Release unused images.",@"image_capture_geometry_invalid"])compare(@[@0,@0,@8,@8],@[@"session",@"run",@"test"],code);
    auto context=parent();reset(context);const unsigned before=imageCaptureCalls;licenseAllowed=false;failure(invoke(@[@0,@0,@8,@8],context),@"license_required task=48");assert(imageCaptureCalls==before);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@0,@0,@8,@8],context),@"AbortError");assert(imageCaptureCalls==before);
    context=parent(.01);reset(context);licenseDelayMs=30;failure(invoke(@[@0,@0,@8,@8],context),@"TimeoutError");assert(imageCaptureCalls==before);
    context=parent(1,1023);reset(context);const int gates=licenseCalls;failure(invoke(@[@0,@0,@8,@8],context),@"response_too_large");assert(licenseCalls==gates&&imageCaptureCalls==before);
    context=parent(1,1024);reset(context);assert([invoke(@[@0,@0,@8,@8],context)[@"ok"] boolValue]);capturedImages.clear();
    for(int fault:{1,2,3,4,5,6}){context=parent();reset(context);imageCaptureFault=fault;failure(invoke(@[@0,@0,@8,@8],context),@"native_exception");assert(capturedImages.empty());}
    context=parent();reset(context);imageCaptureFault=9;failure(invoke(@[@0,@0,@8,@8],context),@"image_capture_failed");assert(capturedImages.empty());
    context=parent();reset(context);imageCaptureFault=7;failure(invoke(@[@0,@0,@8,@8],context),@"AbortError");assert(capturedImages.empty());
    context=parent(.01);reset(context);imageCaptureFault=8;failure(invoke(@[@0,@0,@8,@8],context),@"TimeoutError");assert(capturedImages.empty());
    context=parent();reset(context);cancelImageCapture=true;capturedImages.insert(99);const unsigned rollbacks=imageReleaseCalls;failure(invoke(@[@0,@0,@8,@8],context),@"AbortError");assert(capturedImages.size()==1&&capturedImages.count(99)&&imageReleaseCalls==rollbacks+1);assert(!observedImageRelease.scoped&&observedImageRelease.imageId==41);
    context=parent(.01);reset(context);imageCaptureDelay=30;failure(invoke(@[@0,@0,@8,@8],context),@"TimeoutError");assert(capturedImages.empty());
    context=parent(1,1024);reset(context);hugeImageCaptureReply=true;failure(invoke(@[@0,@0,@8,@8],context),@"response_too_large");assert(capturedImages.empty());
    capturedImages.clear();imageCaptureBudget.reset();imageReleaseBudget.reset();licenseBudget.reset();imageCaptureToken=nil;touchToken=nil;mode=@"echo";
    puts("Typed image capture passed: 240 frozen JS/RAW rounding/owner/result cases, missing/nonfinite input, task-48 gate, floor, caller budget, formatter/backend faults and isolated publication rollback.");
}

static void typedImageOpenCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){mode=@"imageOpenRuntime";imageOpenToken=context.cancellationToken;touchToken=imageOpenToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;imageOpenFault=0;cancelImageOpen=false;imageOpenDelay=0;imageOpenError=nil;hugeImageOpenReply=false;openedImages.clear();};
    const auto request=[](NSString *path)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOpenImage arguments:@[path]];};
    const auto invoke=[bridge,request](NSString *path,TLinkTaskExecutionContext *context)->NSDictionary *{NSDictionary *value=[bridge executeRequest:request(path) context:context error:nil].value;assert(!TLinkCurrentNativeBudget());return value;};
    const auto make=[](NSArray *owners)->TLinkTaskExecutionContext *{auto context=parent(30);context.ownerSessionId=owners[0];context.ownerRunId=owners[1];context.ownerRuntime=owners[2];return context;};
    const auto compare=[bridge,request,invoke,reset,make](NSString *path,NSArray *owners,NSString *code){
        auto oldContext=make(owners);reset(oldContext);imageOpenError=code;const int oldCalls=calls;unsigned oldTracking=trackImages;
        TLinkJSNativeResponse *oldResponse=[bridge legacyImageOpen:request(path) context:oldContext];NSDictionary *old=oldResponse.value;
        const int dispatched=calls-oldCalls;const unsigned tracking=trackImages-oldTracking;auto expected=observedImageOpen;
        auto context=make(owners);reset(context);imageOpenError=code;oldTracking=trackImages;const int before=calls,gates=licenseCalls;const unsigned opens=imageOpenCalls;
        const uint64_t start=TLinkNativeNowNs();NSDictionary *typed=invoke(path,context);const uint64_t end=TLinkNativeNowNs();
        if(typed&&![typed isEqual:old])std::fprintf(stderr,"image open parity: old %s, typed %s\n",[[old description] UTF8String],[[typed description] UTF8String]);
        assert((!old&&!typed)||[typed isEqual:old]);assert(calls==before&&licenseCalls==gates+dispatched&&imageOpenCalls==opens+dispatched&&trackImages-oldTracking==tracking);
        if(dispatched){assert([observedImageOpen.path isEqual:expected.path]&&observedImageOpen.sessionId==expected.sessionId&&observedImageOpen.runId==expected.runId&&observedImageOpen.runtime==expected.runtime&&lastLicenseTask==48);
            assert(imageOpenBudget==licenseBudget&&imageOpenBudget->response().capacity()==0&&imageOpenBudget->deadline()>=start+30000000000ULL&&imageOpenBudget->deadline()<=end+30000000000ULL);}
        if([typed[@"ok"] boolValue])assert(lastTrackedImage==41&&openedImages.count(41));else assert(openedImages.empty());
    };
    unichar nul=0,high=0xd800;NSString *nulString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    NSString *emoji=[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0];
    NSArray *tokens=@[@"owner",@"",@";",@"a;;b",@"a\rb\nc",@" js \t",@"Tiếng Việt",nulString,broken,emoji,[@"x" stringByAppendingString:emoji]];
    NSArray *paths=@[@"image.png",@"/tmp/a.png",@"../image.png",@" image.png \t",@"ảnh🙂.png",@"\ufeffbom.png",@"a;",@";",@"a;;fake;;owner;;runtime",@";;",nulString,broken,@""];
    for(unsigned n=0;n<180;++n)compare(paths[n%paths.count],@[tokens[n%tokens.count],tokens[(n/3)%tokens.count],tokens[(n/7)%tokens.count]],nil);
    for(NSString *code:@[@"image_compute_busy",@"Image not found. Path: /missing",@"image_encoded_limit_or_read_failed",@"image_pixel_limit_or_invalid_metadata",@"image_memory_budget",@"image_decode_dimension_mismatch",@"Image object limit reached. Release unused images."])compare(@"image.png",@[@"session",@"run",@"test"],code);
    auto context=make(@[@"session",@"run",@"test"]);const NSUInteger ownerUnits=TLinkautoJSOwnerSuffix(context).length;
    for(NSUInteger units:{NSUInteger(8192-5-ownerUnits),NSUInteger(8193-5-ownerUnits)})compare([@"p" stringByPaddingToLength:units withString:@"p" startingAtIndex:0],@[@"session",@"run",@"test"],nil);
    context=parent();reset(context);const unsigned before=imageOpenCalls;licenseAllowed=false;failure(invoke(@"image.png",context),@"license_required task=48");assert(imageOpenCalls==before);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@"image.png",context),@"AbortError");assert(imageOpenCalls==before);
    context=parent(.01);reset(context);licenseDelayMs=30;failure(invoke(@"image.png",context),@"TimeoutError");assert(imageOpenCalls==before);
    context=parent(1,1023);reset(context);const int gates=licenseCalls;failure(invoke(@"image.png",context),@"response_too_large");assert(licenseCalls==gates&&imageOpenCalls==before);
    context=parent(1,1024);reset(context);assert([invoke(@"image.png",context)[@"ok"] boolValue]);openedImages.clear();
    for(int fault:{1,2,3,4,5,6}){context=parent();reset(context);imageOpenFault=fault;failure(invoke(@"image.png",context),@"native_exception");assert(openedImages.empty());}
    context=parent();reset(context);imageOpenFault=9;failure(invoke(@"image.png",context),@"image_open_failed");assert(openedImages.empty());
    context=parent();reset(context);imageOpenFault=7;failure(invoke(@"image.png",context),@"AbortError");assert(openedImages.empty());
    context=parent(.01);reset(context);imageOpenFault=8;failure(invoke(@"image.png",context),@"TimeoutError");assert(openedImages.empty());
    context=parent();reset(context);cancelImageOpen=true;openedImages.insert(99);const unsigned rollbacks=imageReleaseCalls;failure(invoke(@"a;;shifted",context),@"AbortError");assert(openedImages.size()==1&&openedImages.count(99)&&imageReleaseCalls==rollbacks+1);assert(!observedImageRelease.scoped&&observedImageRelease.imageId==41);
    context=parent(.01);reset(context);imageOpenDelay=30;failure(invoke(@"image.png",context),@"TimeoutError");assert(openedImages.empty());
    context=parent(1,1024);reset(context);hugeImageOpenReply=true;failure(invoke(@"image.png",context),@"response_too_large");assert(openedImages.empty());
    openedImages.clear();imageOpenBudget.reset();imageReleaseBudget.reset();licenseBudget.reset();imageOpenToken=nil;touchToken=nil;mode=@"echo";
    puts("Typed image open passed: 180 frozen JS/RAW path/owner/results, delimiter overlap/UTF8/NUL, exact 8192/8193 ingress, task-48 gate, floor, caller budget, faults and isolated publication rollback.");
}
static void typedFrameCaptureCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){mode=@"frameCaptureRuntime";captureToken=context.cancellationToken;touchToken=captureToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameCaptureFault=0;cancelFrameCapture=false;frameCaptureDelay=0;frameCaptureError=nil;hugeCaptureReply=false;capturedFrames.clear();};
    const auto request=[](NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodCaptureFrame arguments:@[options]];};
    const auto invoke=[bridge,request](NSDictionary *options,TLinkTaskExecutionContext *context)->NSDictionary *{NSDictionary *value=[bridge executeRequest:request(options) context:context error:nil].value;assert(!TLinkCurrentNativeBudget());return value;};
    const auto make=[](NSArray *owners)->TLinkTaskExecutionContext *{auto context=parent(30);context.ownerSessionId=owners[0];context.ownerRunId=owners[1];context.ownerRuntime=owners[2];return context;};
    const auto compare=[bridge,request,invoke,reset,make](NSDictionary *options,NSArray *owners,NSString *code){
        auto oldContext=make(owners);reset(oldContext);frameCaptureError=code;const int oldCalls=calls;unsigned oldTracking=trackFrames;
        NSDictionary *old=[bridge legacyFrameCapture:request(options) context:oldContext].value;const int dispatched=calls-oldCalls;const unsigned tracking=trackFrames-oldTracking;auto expected=observedFrameCapture;
        auto context=make(owners);reset(context);frameCaptureError=code;oldTracking=trackFrames;const int before=calls,gates=licenseCalls;const unsigned captures=frameCaptureCalls;uint64_t start=TLinkNativeNowNs();NSDictionary *typed=invoke(options,context);uint64_t end=TLinkNativeNowNs();
        if(![typed isEqual:old])std::fprintf(stderr,"frame capture parity: old %s, typed %s\n",[[old description] UTF8String],[[typed description] UTF8String]);
        assert([typed isEqual:old]&&calls==before&&licenseCalls==gates+dispatched&&frameCaptureCalls==captures+dispatched&&trackFrames-oldTracking==tracking);
        if(dispatched){assert(observedFrameCapture.gray==expected.gray&&observedFrameCapture.bgra==expected.bgra&&observedFrameCapture.ttlMs==expected.ttlMs);
            assert(observedFrameCapture.sessionId==expected.sessionId&&observedFrameCapture.runId==expected.runId&&observedFrameCapture.runtime==expected.runtime&&lastLicenseTask==66);
            assert(frameCaptureBudget==licenseBudget&&frameCaptureBudget->response().capacity()==0&&frameCaptureBudget->deadline()>=start+30000000000ULL&&frameCaptureBudget->deadline()<=end+30000000000ULL);}
        if([typed[@"ok"] boolValue])assert(lastTrackedFrame==41&&capturedFrames.count(41));else assert(capturedFrames.empty());
    };
    unichar nul=0,high=0xd800;NSString *nulString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    NSString *emoji=[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0];NSArray *tokens=@[@"session",@"",@";",@"owner;",@";owner",@"a;;b",@"a\rb\nc",@" runtime \t",@"Tiếng Việt",nulString,broken,emoji,[@"x" stringByAppendingString:emoji]];
    for(unsigned n=0;n<160;++n)compare(@{@"gray":@(int(n%5)-2),@"bgra":@(int(n%3)-1),@"ttlMs":n%2?@(-1):@(int(n)*100)},@[tokens[n%tokens.count],tokens[(n/3)%tokens.count],tokens[(n/7)%tokens.count]],nil);
    for(NSString *code:@[@"image_compute_busy",@"capture_failed",@"frame_pixel_limit",@"frame_memory_budget",@"bgra_render_failed",@"gray_convert_failed",@"frame_publish_failed"])compare(@{},@[@"session",@"run",@"test"],code);
    auto context=parent();reset(context);const unsigned before=frameCaptureCalls;licenseAllowed=false;failure(invoke(@{},context),@"license_required task=66");assert(frameCaptureCalls==before);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@{},context),@"AbortError");assert(frameCaptureCalls==before);
    context=parent(.01);reset(context);licenseDelayMs=30;failure(invoke(@{},context),@"TimeoutError");assert(frameCaptureCalls==before);
    context=parent(1,1023);reset(context);const int gates=licenseCalls;failure(invoke(@{},context),@"response_too_large");assert(licenseCalls==gates&&frameCaptureCalls==before);
    context=parent(1,1024);reset(context);assert([invoke(@{},context)[@"ok"] boolValue]);capturedFrames.clear();
    for(int fault:{1,2,3,4,5,6}){context=parent();reset(context);frameCaptureFault=fault;failure(invoke(@{},context),@"native_exception");assert(capturedFrames.empty());}
    context=parent();reset(context);frameCaptureFault=7;failure(invoke(@{},context),@"AbortError");assert(capturedFrames.empty());
    context=parent();reset(context);cancelFrameCapture=true;unsigned rollbacks=frameReleaseCalls;failure(invoke(@{},context),@"AbortError");assert(capturedFrames.empty()&&frameReleaseCalls==rollbacks+1);
    context=parent(.01);reset(context);frameCaptureDelay=30;failure(invoke(@{},context),@"TimeoutError");assert(capturedFrames.empty());
    context=parent(1,1024);reset(context);hugeCaptureReply=true;failure(invoke(@{},context),@"response_too_large");assert(capturedFrames.empty());
    frameCaptureBudget.reset();frameReleaseBudget.reset();licenseBudget.reset();mode=@"echo";captureToken=nil;touchToken=nil;hugeCaptureReply=false;
    puts("Typed frame capture passed: 160 frozen JS/RAW option/owner/metadata cases, one task-66 gate, caller deadline, 1024-byte floor, faults and rollback after publication/cancel/expiry/output.");
}
static void typedImageReleaseCases(TLinkInProcessNativeBridge *bridge){
    const auto make=[](NSArray *owners)->TLinkTaskExecutionContext *{auto context=parent(30);context.ownerSessionId=owners[0];context.ownerRunId=owners[1];context.ownerRuntime=owners[2];return context;};
    const auto request=[](int id)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodReleaseImage arguments:@[@(id)]];};
    const auto invoke=[bridge,request](int id,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{TLinkJSNativeResponse *reply=[bridge executeRequest:request(id) context:context error:nil];assert(!TLinkCurrentNativeBudget());return reply;};
    const auto compare=[bridge,request,make,invoke](int id,NSArray *owners){
        mode=@"imageReleaseRuntime";imageReleaseFault=0;
        auto oldContext=make(owners);const int oldCalls=calls;unsigned oldTracking=untrackImages;
        NSDictionary *old=[bridge legacyImageRelease:request(id) context:oldContext].value;const int dispatched=calls-oldCalls;
        const unsigned tracking=untrackImages-oldTracking;auto expected=observedImageRelease;
        auto context=make(owners);oldTracking=untrackImages;const int before=calls,gates=licenseCalls;const unsigned backend=imageReleaseCalls;
        NSDictionary *typed=invoke(id,context).value;
        if(![typed isEqual:old])std::fprintf(stderr,"image release parity: old %s, typed %s\n",[[old description] UTF8String],[[typed description] UTF8String]);
        assert([typed isEqual:old]&&calls==before&&licenseCalls==gates&&imageReleaseCalls==backend+dispatched&&untrackImages-oldTracking==tracking);
        if(dispatched){assert(observedImageRelease.imageId==expected.imageId&&observedImageRelease.all==expected.all&&observedImageRelease.scoped==expected.scoped);
            assert(observedImageRelease.sessionId==expected.sessionId&&observedImageRelease.runId==expected.runId&&observedImageRelease.runtime==expected.runtime&&lastUntrackedImage==id);}
    };
    unichar nul=0,high=0xd800;NSString *nulString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    NSString *emoji=[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0];
    NSArray *tokens=@[@"session",@"",@";",@"owner;",@";owner",@"a;;b",@"a\rb\nc",@" runtime \t",@"Tiếng Việt",nulString,broken,emoji,[@"x" stringByAppendingString:emoji]];
    for(unsigned n=0;n<160;++n){imageReleaseCount=n%2;compare(n%13==0?-1:int(n%11),@[tokens[n%tokens.count],tokens[(n/3)%tokens.count],tokens[(n/7)%tokens.count]]);}
    compare(1,@[@"session",@"run",@"js \t"]);assert(observedImageRelease.runtime=="js \t");
    imageReleaseCount=1;mode=@"imageReleaseRuntime";const int gates=licenseCalls;const unsigned before=imageReleaseCalls;
    auto context=parent();[context.cancellationToken cancel];licenseAllowed=false;
    assert([invoke(42,context).value[@"ok"] boolValue]&&imageReleaseCalls==before+1&&licenseCalls==gates);
    context=parent();[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    assert([invoke(42,context).value[@"ok"] boolValue]&&imageReleaseCalls==before+2&&licenseCalls==gates);licenseAllowed=true;
    context=parent();auto overflowing=std::make_shared<TLinkNativeBudget>(nullptr,0,1);assert(!overflowing->outputAllowed(2));[context setNativeBudget:overflowing];
    assert([invoke(42,context).value[@"ok"] boolValue]&&imageReleaseCalls==before+3);
    const NSUInteger bytes=[@"0;;1\r\n" lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    assert([invoke(42,parent(1,bytes)).value[@"ok"] boolValue]);unsigned untracked=untrackImages;const unsigned effects=imageReleaseCalls;
    failure(invoke(42,parent(1,bytes-1)).value,@"response_too_large");assert(imageReleaseCalls==effects+1&&untrackImages==untracked);
    for(int fault:{1,2}){imageReleaseFault=fault;failure(invoke(42,parent()).value,@"native_exception");assert(untrackImages==untracked);}
    imageReleaseFault=0;imageReleaseBudget.reset();mode=@"echo";
    puts("Typed image release passed: 160 frozen JS/RAW owner/encoding/tracking/count cases, exact trailing whitespace, cleanup after cancel/expiry/denial/overflow, output-cap effects and NS/C++ faults without RAW/sink/license gate.");
}
static void typedFrameReleaseCases(TLinkInProcessNativeBridge *bridge){
    const auto make=[](NSArray *owners)->TLinkTaskExecutionContext *{auto context=parent(30);context.ownerSessionId=owners[0];context.ownerRunId=owners[1];context.ownerRuntime=owners[2];return context;};
    const auto request=[](bool all,int id)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:all?TLinkJSNativeMethodReleaseAllFrames:TLinkJSNativeMethodReleaseFrame arguments:all?@[]:@[@(id)]];};
    const auto invoke=[bridge,request](bool all,int id,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{TLinkJSNativeResponse *reply=[bridge executeRequest:request(all,id) context:context error:nil];assert(!TLinkCurrentNativeBudget());return reply;};
    const auto compare=[bridge,request,make,invoke](bool all,int id,NSArray *owners){
        mode=@"frameReleaseRuntime";frameReleaseFault=0;
        auto oldContext=make(owners);const int oldCalls=calls;unsigned oldOne=untrackFrames,oldAll=untrackAllFrames;
        NSDictionary *old=[bridge legacyFrameRelease:request(all,id) context:oldContext].value;const int dispatched=calls-oldCalls;
        const unsigned one=untrackFrames-oldOne,many=untrackAllFrames-oldAll;auto expected=observedFrameRelease;
        auto context=make(owners);oldOne=untrackFrames;oldAll=untrackAllFrames;const int before=calls,gates=licenseCalls;const unsigned backend=frameReleaseCalls;
        NSDictionary *typed=invoke(all,id,context).value;
        if(![typed isEqual:old])std::fprintf(stderr,"frame release parity: old %s, typed %s\n",[[old description] UTF8String],[[typed description] UTF8String]);
        assert([typed isEqual:old]&&calls==before&&licenseCalls==gates&&frameReleaseCalls==backend+dispatched);
        assert(untrackFrames-oldOne==one&&untrackAllFrames-oldAll==many);
        if(dispatched){assert(observedFrameRelease.frameId==expected.frameId&&observedFrameRelease.all==expected.all&&observedFrameRelease.scoped==expected.scoped);
            assert(observedFrameRelease.sessionId==expected.sessionId&&observedFrameRelease.runId==expected.runId&&observedFrameRelease.runtime==expected.runtime);if(!all)assert(lastUntrackedFrame==id);}
    };
    unichar nul=0,high=0xd800;NSString *nulString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    NSArray *tokens=@[@"session",@"",@";",@"owner;",@";owner",@"a;;b",@"a\rb\nc",@" runtime \t",@"Tiếng Việt",nulString,broken,[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0],[@"x" stringByAppendingString:[@"🙂" stringByPaddingToLength:120 withString:@"🙂" startingAtIndex:0]]];
    for(unsigned n=0;n<160;++n){frameReleaseCount=n%4;compare(n%5==0,n%13==0?-1:int(n%11),@[tokens[n%tokens.count],tokens[(n/3)%tokens.count],tokens[(n/7)%tokens.count]]);}
    frameReleaseCount=1;mode=@"frameReleaseRuntime";const int gates=licenseCalls;const unsigned before=frameReleaseCalls;
    auto context=parent();[context.cancellationToken cancel];licenseAllowed=false;
    assert([invoke(false,42,context).value[@"ok"] boolValue]&&frameReleaseCalls==before+1&&licenseCalls==gates);
    context=parent();[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    assert([invoke(true,0,context).value[@"ok"] boolValue]&&frameReleaseCalls==before+2&&licenseCalls==gates);licenseAllowed=true;
    const NSUInteger bytes=[@"0;;1\r\n" lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    assert([invoke(false,42,parent(1,bytes)).value[@"ok"] boolValue]);unsigned untracked=untrackFrames;const unsigned effects=frameReleaseCalls;
    failure(invoke(false,42,parent(1,bytes-1)).value,@"response_too_large");assert(frameReleaseCalls==effects+1&&untrackFrames==untracked);
    for(int fault:{1,2}){frameReleaseFault=fault;failure(invoke(false,42,parent()).value,@"native_exception");assert(untrackFrames==untracked);}
    frameReleaseFault=0;frameReleaseBudget.reset();mode=@"echo";
    puts("Typed frame release passed: 160 frozen JS/RAW owner/encoding/tracking/count cases, no RAW/sink/license gate, cleanup after cancel/expiry/denial, output-cap effects and NS/C++ faults.");
}
static void typedFrameOCRCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameOCRFault=0;frameOCRError=nil;cancelFrameOCR=false;customOCRResult=false;};
    const auto request=[](int fid,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOcrFrame arguments:@[@(fid),options]];};
    const auto invoke=[bridge,request](int fid,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{TLinkJSNativeResponse *result=[bridge executeRequest:request(fid,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;};
    const auto compare=[bridge,request,invoke,reset](int fid,NSDictionary *options,NSString *backendError){
        mode=@"frameOCRRuntime";auto oldContext=parent(30);reset(oldContext);frameOCRError=backendError;const int oldCalls=calls;TLinkJSNativeResponse *legacy=[bridge legacyFrameOCR:request(fid,options) context:oldContext];const int dispatched=calls-oldCalls;
        auto context=parent(30);reset(context);frameOCRError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=frameOCRCalls;const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(fid,options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame OCR parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&frameOCRCalls==reads+dispatched);if(dispatched){assert(lastLicenseTask==91&&frameOCRBudget==licenseBudget&&!frameOCRBudget->capturesResponse()&&frameOCRBudget->response().capacity()==0);assert(frameOCRBudget->deadline()>=started+3000000000ULL&&frameOCRBudget->deadline()<=ended+3000000000ULL);}
    };
    // OCR success has columns after status 0; touch's exact "0\r\n" reply is insufficient.
    auto successContext=parent(30);reset(successContext);NSDictionary *structured=invoke(1,@{},successContext).value;
    if(![structured[@"ok"] boolValue])std::fprintf(stderr,"typed frame OCR must accept status-0 body: %s\n",[[structured description] UTF8String]);
    assert([structured[@"ok"] boolValue]&&[structured[@"parts"] count]==7&&[structured[@"text"] length]>0);
    assert([structured[@"confidence"] doubleValue]==83.12&&[structured[@"ageMs"] unsignedLongLongValue]==42);
    for(unsigned n=0;n<100;++n){const double x=n<8?std::vector<double>{-1e308,double(INT_MIN),-.5,-0.0,.5,1.5,double(INT_MAX),1e308}[n]:double(int(n%19)-3)*.5;compare(1,@{@"x":@(x),@"y":@1.5,@"width":@(double(int(n%9)-2)*.5),@"lang":n%3?@"eng":@"",@"coord":n%2?@"point":@"pixel",@"whitelist":@"đọc ;;A\n",@"oem":@(int(n%7)-2),@"psm":@(n%17),@"scaleUp":@(int(n%7)-1),@"thresholdMode":@(n%4),@"maxAgeMs":@(int(n%3)-1)},nil);}
    NSDictionary *normal=@{};compare(1,normal,nil);compare(0,normal,nil);compare(1,@{@"x":@(NAN)},nil);compare(1,@{@"height":@(INFINITY)},nil);compare(1,@{@"lang":@"en;;x"},nil);compare(1,@{@"coord":@"pixel\n"},nil);
    unichar nul=0,high=0xd800;NSString *nullString=[NSString stringWithCharacters:&nul length:1],*broken=[NSString stringWithCharacters:&high length:1];
    for(NSString *token:@[nullString,broken,@"điểm",@""]){compare(1,@{@"lang":token},nil);compare(1,@{@"coord":token},nil);compare(1,@{@"whitelist":token},nil);}
    NSString *empty=@"911;;0;;0;;0;;0;;;;1;;7;;;;2;;0;;pixel;;1000";const NSUInteger limit=8192-empty.length;
    for(unsigned extra=0;extra<2;++extra){compare(1,@{@"lang":[@"x" stringByPaddingToLength:limit+extra withString:@"x" startingAtIndex:0]},nil);compare(1,@{@"lang":[nullString stringByPaddingToLength:limit+extra withString:@"x" startingAtIndex:0]},nil);}
    compare(1,@{@"whitelist":[@"界" stringByPaddingToLength:3000 withString:@"界" startingAtIndex:0]},nil);
    for(NSString *code:@[@"disabled",@"ocr_busy",@"ocr_scaled_image_too_large",@"engine_init_failed",@"ocr_exception",@"ocr_cancelled_or_timed_out"])compare(1,normal,code);
    const double confidenceCases[]={-1.0,-0.0,.005,83.125,99.995};
    for(unsigned n=0;n<80;++n){
        auto context=parent(30);reset(context);customOCRResult=true;
        publishedOCRResult=TLinkFormatFrameOCRValue(n%2?@"Tiếng Việt ;; A\n🙂":nullString,confidenceCases[n%5],n%3?42:UINT64_MAX,double(n)*.0005,2.3455,3.4565);
        NSDictionary *typed=invoke(1,normal,context).value;
        mode=@"frameOCRRuntime";TLinkJSNativeResponse *legacy=[bridge legacyFrameOCR:request(1,normal) context:parent(30)];
        assert([typed[@"ok"] boolValue]&&[typed isEqual:legacy.value]);customOCRResult=false;
    }
    const int wireCalls=calls;auto context=parent();reset(context);licenseAllowed=false;const unsigned reads=frameOCRCalls;NSDictionary *denied=invoke(1,normal,context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=91\r\n"]&&frameOCRCalls==reads);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,normal,context).value,@"AbortError");assert(frameOCRCalls==reads);context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(1,normal,context).value,@"AbortError");assert(licenseCalls==gates&&frameOCRCalls==reads);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(1,normal,context).value,@"TimeoutError");assert(licenseCalls==gates);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];NSDictionary *expired=invoke(1,normal,context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameOCRCalls==reads);
    context=parent();reset(context);cancelFrameOCR=true;failure(invoke(1,normal,context).value,@"AbortError");for(int fault:{1,2}){context=parent();reset(context);frameOCRFault=fault;failure(invoke(1,normal,context).value,@"native_exception");}
    context=parent();reset(context);NSDictionary *success=invoke(1,normal,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];context=parent(1,bytes);reset(context);assert([invoke(1,normal,context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(1,normal,context).value,@"response_too_large");
    publishedOCRResult=TLinkNativeFrameOCRValue();
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameOCRBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";puts("Typed frame OCR passed: 100 frozen JS/RAW input cases, 80 structured result cases, Foundation int/age/whitelist normalization, exact ingress/encoding, decoded errors/results, one task-91 gate, C01/caller/cancel/fault/output and no typed RAW dispatch.");
}
static void typedFramePickCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto invoke=[bridge](int id,double x,double y,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFramePickColor arguments:@[@(id),@(x),@(y),options]];
        TLinkJSNativeResponse *response=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return response;
    };
    const int wireCalls=calls;
    for(unsigned trial=0;trial<100;++trial){
        double x=trial<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2147483647.0,1e308}[trial]:double(trial)*47.125;
        const double y=double(trial)*0.5;auto context=parent(30);reset(context);const int gates=licenseCalls;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *response=invoke(1,x,y,@{@"coord":trial%2?@"PoInT":@"pixel",@"maxAgeMs":@5000},context);
        assert(response.ok&&licenseCalls==gates+1&&lastLicenseTask==69&&frameBudget==licenseBudget&&frameBudget->response().capacity()==0);
        const uint64_t after=TLinkNativeNowNs();assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);
        NSString *wire=[NSString stringWithFormat:@"%.0f;;%.0f",x,y];NSArray *numbers=[wire componentsSeparatedByString:@";;"];
        assert(observedFramePick.x==[numbers[0] doubleValue]&&observedFramePick.y==[numbers[1] doubleValue]&&observedFramePick.pointCoord==bool(trial%2)&&observedFramePick.maxAgeMs==5000);
        NSDictionary *result=response.value;
        if(!TLinkFramePickParameters(observedFramePick)){failure(result,@"invalid_frame_color_parameters");continue;}
        NSString *expected=@"0;;1;;2;;3;;7;;1.235;;1.235\r\n";
        assert([result[@"raw"] isEqualToString:expected]&&[result[@"ok"] boolValue]);
        assert([result[@"parts"] isEqualToArray:[[expected stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert([result[@"red"] intValue]==1&&[result[@"green"] intValue]==2&&[result[@"blue"] intValue]==3&&[result[@"ageMs"] intValue]==7&&[result[@"totalMs"] doubleValue]==1.235);
    }
    auto context=parent();reset(context);const unsigned noRead=frameReads;const int noGate=licenseCalls;
    assert(!invoke(0,0,0,@{},context).ok&&!invoke(1,NAN,0,@{},context).ok&&!invoke(1,0,INFINITY,@{},context).ok);
    for(NSString *bad:@[@"pixel;;x",@"pixel\r",@"pixel\n"])assert(!invoke(1,0,0,@{@"coord":bad},context).ok);
    assert(frameReads==noRead&&licenseCalls==noGate);
    unichar nul=0;NSString *nulToken=[NSString stringWithCharacters:&nul length:1];
    NSString *nulCoord=[@"pi" stringByAppendingString:nulToken];
    unichar high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};
    NSString *invalidHigh=[NSString stringWithCharacters:&high length:1],*invalidLow=[NSString stringWithCharacters:&low length:1];
    NSString *paired=[NSString stringWithCharacters:pair length:2];
    NSArray *encodingProbes=@[nulToken,nulCoord,[nulToken stringByAppendingString:@"pixel"],
        [@"pi" stringByAppendingString:[nulToken stringByAppendingString:@"xel"]],invalidHigh,invalidLow,
        [@"pi" stringByAppendingString:invalidHigh],paired,@"",@"điểm",
        [nulToken stringByPaddingToLength:8169 withString:@"x" startingAtIndex:0],
        [nulToken stringByPaddingToLength:8170 withString:@"x" startingAtIndex:0]];
    int oracleDispatches=0;
    for(NSString *coord:encodingProbes){
        // Use the actual legacy formatter/transport as the oracle for Foundation string conversion.
        mode=@"frameEncodingOracle";const int beforeOracle=calls;
        NSString *wire=[NSString stringWithFormat:@"691;;pick;;0;;0;;%@;;1000",coord];
        NSDictionary *legacy=[bridge executeRawPayload:wire context:parent()];
        const int dispatched=calls-beforeOracle;assert(dispatched==0||dispatched==1);oracleDispatches+=dispatched;
        mode=@"echo";context=parent();reset(context);
        const int beforeGate=licenseCalls,beforeTyped=calls;const unsigned beforeRead=frameReads;
        NSDictionary *result=invoke(1,0,0,@{@"coord":coord},context).value;
        failure(result,legacy[@"parts"][1]);assert([result isEqualToDictionary:legacy]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameReads==beforeRead+dispatched);
    }
    for(unsigned extra=0;extra<2;++extra){context=parent();reset(context);const int beforeGate=licenseCalls;
        NSString *coord=[@"x" stringByPaddingToLength:8169+extra withString:@"x" startingAtIndex:0];
        NSString *wire=[NSString stringWithFormat:@"691;;pick;;0;;0;;%@;;1000",coord];assert(wire.length==8192+extra);
        NSDictionary *result=invoke(1,0,0,@{@"coord":coord},context).value;
        failure(result,extra?@"input_too_large":@"invalid_frame_color_parameters");assert(licenseCalls==beforeGate+(extra?0:1));
    }
    for(NSDictionary *options:@[@{@"coord":@"typo"},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001}]){context=parent();reset(context);failure(invoke(1,0,0,options,context).value,@"invalid_frame_color_parameters");}
    context=parent();reset(context);licenseAllowed=false;const unsigned beforeDenial=frameReads;
    NSDictionary *denied=invoke(1,0,0,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameReads==beforeDenial);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,0,0,@{},context).value,@"AbortError");assert(frameReads==beforeDenial);
    context=parent();reset(context);[context.cancellationToken cancel];const int stoppedGate=licenseCalls;
    failure(invoke(1,0,0,@{},context).value,@"AbortError");assert(licenseCalls==stoppedGate&&frameReads==beforeDenial);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,0,0,@{},context).value,@"TimeoutError");assert(licenseCalls==stoppedGate&&frameReads==beforeDenial);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,0,0,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameReads==beforeDenial);
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"]){
        context=parent();reset(context);frameReadError=code;failure(invoke(1,0,0,@{},context).value,code);
    }
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,0,0,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,0,0,@{},context).value,@"native_exception");}
    const NSUInteger successBytes=[@"0;;1;;2;;3;;7;;1.235;;1.235\r\n" length];
    context=parent(1,successBytes);reset(context);assert([invoke(1,0,0,@{},context).value[@"ok"] boolValue]);
    context=parent(1,successBytes-1);reset(context);failure(invoke(1,0,0,@{},context).value,@"response_too_large");
    assert(calls==wireCalls+oracleDispatches&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;
    puts("Typed frame pick actual bridge/entry passed: scalar/RGB/age/time/parts parity, exact 8192/8193 input, 12 legacy NUL/UTF/size admission cases, one task-69 gate, C01/caller deadlines, faults/output and no raw dispatch.");
}
static void typedFramePickManyCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](NSArray *points,NSDictionary *options){return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFramePickColors arguments:@[@1,points,options]];};
    const auto invoke=[bridge,request](NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameManyRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameMany:request(points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameManyReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(points,options,context);const uint64_t after=TLinkNativeNowNs();
        assert(typed.ok==legacy.ok);
        if(typed.ok){
            if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame many parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);
            assert([typed.value isEqual:legacy.value]);
        }else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameManyReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<120;++i){
        double x=i<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2147483647.0,1e308}[i]:double(i)*17.125;
        compare(@[@[@(x),@(double(i)*0.5)],@{@"x":@1,@"y":@2},@{}],@{@"coord":i%2?@"PoInT":@"pixel",@"maxAgeMs":@5000},nil);
    }
    compare(@[@[@"2.5",@"3.5",@999],@{}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@[@(NAN),@0]],@[@[@0,@(INFINITY)]]])compare(bad,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@[@0,@0]];
    compare(many,@{},nil);[many addObject:@[@0,@0]];compare(many,@{},nil);compare(many,@{},@"frame_expired");compare(many,@{},@"frame_not_found");
    [many addObject:@[]];compare(many,@{},nil); // full JS validation survives a lazy count failure
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@[@(1e308),@0]];
    compare(many,@{},nil);[many addObject:@[]];compare(many,@{},nil); // late shape error before oversized ingress
    NSArray *points=@[@[@0,@0]];
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],
        [NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(points,@{@"coord":coord},nil);
    for(unsigned extra=0;extra<2;++extra){
        NSString *coord=[@"x" stringByPaddingToLength:8165+extra withString:@"x" startingAtIndex:0];
        NSString *wire=[NSString stringWithFormat:@"691;;pick_many;;0,0;;%@;;1000",coord];assert(wire.length==8192+extra);compare(points,@{@"coord":coord},nil);
        coord=[nulString stringByPaddingToLength:8165+extra withString:@"x" startingAtIndex:0];compare(points,@{@"coord":coord},nil);
    }
    for(NSDictionary *options:@[@{@"coord":@"typo"},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(points,options,nil);
    const int wireCalls=calls;
    auto context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameManyReads;
    NSDictionary *denied=invoke(points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameManyReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(points,@{},context).value,@"AbortError");assert(frameManyReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameManyReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameManyReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameManyReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(points,@{},context).value,@"native_exception");}
    context=parent();reset(context);NSDictionary *success=invoke(points,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    context=parent(1,bytes);reset(context);assert([invoke(points,@{},context).value[@"ok"] boolValue]);
    context=parent(1,bytes-1);reset(context);failure(invoke(points,@{},context).value,@"response_too_large");
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame pick-many actual bridge/entry passed: 120 frozen JS/RAW parity cases, mixed point shapes, 512/513 and full prevalidation, exact 8192/8193 and Unicode/NUL admission, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameSearchCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameFindColor arguments:@[@(id),options]];};
    const auto invoke=[bridge,request](int id,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSDictionary *options,NSString *backendError){
        mode=@"frameSearchRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameSearch:request(id,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameSearchReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,options,context);const uint64_t after=TLinkNativeNowNs();
        assert(typed.ok==legacy.ok);
        if(typed.ok){
            if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame search parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);
            assert([typed.value isEqual:legacy.value]);
        }else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameSearchReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        double x=i<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,7.5,2147483646.0,1e308}[i]:double(int(i%13)-3)*0.5;
        compare(1,@{@"x":@(x),@"y":@(double(i%7)*0.5),@"width":@(int(i%9)-2),@"height":@0,@"coord":i%2?@"PoInT":@"pixel",@"skip":@(i%4),@"redMin":@5,@"redMax":@5,@"greenMin":@3,@"greenMax":@3,@"blueMin":@2,@"blueMax":@2,@"maxAgeMs":@5000},nil);
    }
    compare(1,@{},nil);compare(1,@{@"rMin":@5,@"rMax":@5,@"gMin":@3,@"gMax":@3,@"bMin":@2,@"bMax":@2},nil);
    compare(1,@{@"rMin":@5,@"redMin":@0,@"redMax":@14,@"skip":@1023},nil);
    for(NSDictionary *options:@[@{@"redMin":@-1},@{@"redMax":@256},@{@"greenMin":@20,@"greenMax":@19},@{@"blueMin":@256},@{@"skip":@-1},@{@"skip":@1024},@{@"skip":@(INT_MAX)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0},@{@"x":@(NAN)},@{@"width":@(INFINITY)}])compare(1,options,nil);
    compare(0,@{},nil);compare(-1,@{},nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],
        [NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,@{@"coord":coord},nil);
    NSString *emptyWire=@"691;;search_single;;0;;0;;0;;0;;0;;255;;0;;255;;0;;255;;0;;;;1000";
    const NSUInteger maxCoord=8192-emptyWire.length;
    for(unsigned extra=0;extra<2;++extra){
        NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,@{@"coord":coord},nil);
        coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,@{@"coord":coord},nil);
    }
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,@{@"x":@(double(INT_MAX)-1),@"coord":@"point"},code);
    const int wireCalls=calls;auto context=parent();reset(context);
    NSDictionary *miss=invoke(1,@{@"redMin":@255},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&[miss[@"x"] intValue]==-1&&[miss[@"y"] intValue]==-1&&[miss[@"red"] intValue]==-1&&[miss[@"green"] intValue]==-1&&[miss[@"blue"] intValue]==-1);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameSearchReads;
    NSDictionary *denied=invoke(1,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameSearchReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,@{},context).value,@"AbortError");assert(frameSearchReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameSearchReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameSearchReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameSearchReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,@{},context).value,@"native_exception");}
    for(NSDictionary *options:@[@{},@{@"redMin":@255}]){
        context=parent();reset(context);NSDictionary *success=invoke(1,options,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,options,context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,options,context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame search actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/RGB/ROI/skip, hit/miss metadata, exact ingress/Unicode/NUL, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameColorsCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameIsColors arguments:@[@(id),points,options]];};
    const auto invoke=[bridge,request](int id,NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameColorsRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameColors:request(id,points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameColorsReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,points,options,context);const uint64_t after=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame colors parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameColorsReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<9?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),1e308}[i]:double(int(i%17)-3)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(1,@[@{@"x":@(x),@"y":@1.5,@"r":@4,@"g":@2,@"b":@2},@{}],@{@"coord":i%3?@"pixel":@"PoInT",@"mode":@(modeValue),@"value":@(threshold),@"maxAgeMs":@5000},nil);
    }
    NSArray *points=@[@{}],*missPoints=@[@{@"red":@255}],*badTable=@[@{@"red":@255},@{@"red":@999}];
    compare(1,points,@{},nil);compare(1,missPoints,@{},nil);compare(1,badTable,@{},nil);
    compare(1,@[@{@"red":@1,@"r":@0}],@{},nil);compare(1,@[@{@"red":[NSNull null],@"r":@0}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(1,bad,@{},nil);
    compare(0,points,@{},nil);compare(-1,points,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(1,many,@{},nil);[many addObject:@{}];compare(1,many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(1,many,@{},nil);[many addObject:@[]];compare(1,many,@{},nil);
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(1,points,options,nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],[NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,points,@{@"coord":coord},nil);
    for(double threshold:{0.0,-0.0,-0.00004,0.99995,255.00004,1e308,double(NAN),double(-NAN),double(INFINITY),double(-INFINITY)}){
        NSString *scalar=[NSString stringWithFormat:@"%.4f",threshold];
        NSString *emptyWire=[NSString stringWithFormat:@"691;;is_colors;;0,,0,,0,,0,,0;;1;;%@;;;;1000",scalar];const NSUInteger maxCoord=8192-emptyWire.length;
        for(unsigned extra=0;extra<2;++extra){
            NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
            coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
        }
    }
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,badTable,@{},code);
    const int wireCalls=calls;auto context=parent();reset(context);NSDictionary *miss=invoke(1,missPoints,@{},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&![miss[@"value"] boolValue]);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameColorsReads;
    NSDictionary *denied=invoke(1,points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameColorsReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,points,@{},context).value,@"AbortError");assert(frameColorsReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameColorsReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameColorsReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameColorsReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,points,@{},context).value,@"native_exception");}
    for(NSArray *list:@[points,missPoints]){
        context=parent();reset(context);NSDictionary *success=invoke(1,list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,list,@{},context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,list,@{},context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame colors actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/defaults/full table preflight, 512/513 and exact ingress/Unicode/NUL, scalar rounding/nonfinite modes, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameMultiCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameFindMultiColor arguments:@[@(id),points,options]];};
    const auto invoke=[bridge,request](int id,NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameMultiRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameMulti:request(id,points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameMultiReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,points,options,context);const uint64_t after=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame multi parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameMultiReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<9?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),1e308}[i]:double(int(i%17)-3)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(1,@[@{@"x":@(x),@"y":@1.5,@"r":@4,@"g":@2,@"b":@2},@{}],@{@"coord":i%3?@"pixel":@"PoInT",@"mode":@(modeValue),@"value":@(threshold),@"maxAgeMs":@5000,@"x":@(double(int(i%9)-2)*0.5),@"y":@(-0.0),@"width":@(i%5),@"height":@0,@"skip":@(i%4)},nil);
    }
    NSArray *points=@[@{}],*missPoints=@[@{@"red":@255}],*badTable=@[@{@"red":@255},@{@"red":@999}];
    compare(1,points,@{},nil);compare(1,missPoints,@{},nil);compare(1,badTable,@{},nil);
    compare(1,@[@{@"red":@1,@"r":@0}],@{},nil);compare(1,@[@{@"red":[NSNull null],@"r":@0}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(1,bad,@{},nil);
    compare(0,points,@{},nil);compare(-1,points,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(1,many,@{},nil);[many addObject:@{}];compare(1,many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(1,many,@{},nil);[many addObject:@[]];compare(1,many,@{},nil);
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(1,points,options,nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],[NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,points,@{@"coord":coord},nil);
    for(double threshold:{0.0,-0.0,-0.00004,0.99995,255.00004,1e308,double(NAN),double(-NAN),double(INFINITY),double(-INFINITY)}){
        NSString *scalar=[NSString stringWithFormat:@"%.4f",threshold];
        NSString *emptyWire=[NSString stringWithFormat:@"691;;find_multi_point;;0;;0;;0;;0;;0,,0,,0,,0,,0;;1;;%@;;0;;;;1000",scalar];const NSUInteger maxCoord=8192-emptyWire.length;
        for(unsigned extra=0;extra<2;++extra){
            NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
            coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
        }
    }
    for(NSDictionary *options:@[@{@"x":@(NAN)},@{@"height":@(INFINITY)},@{@"skip":@-1},@{@"skip":@1024},@{@"skip":@1023},@{@"coord":@"point",@"width":@(double(INT_MAX)-1)},@{@"x":@(-100),@"y":@100},@{@"x":@2,@"y":@2,@"width":@1,@"height":@1}])compare(1,points,options,nil);
    compare(1,@[@{@"x":@-1,@"red":@2,@"green":@2}],@{@"coord":@"point",@"x":@1,@"y":@1,@"width":@1,@"height":@1,@"mode":@0,@"value":@1},nil);
    compare(1,@[@{@"x":@(INT_MAX)},@{@"red":@999}],@{@"coord":@"point"},nil);
    compare(1,badTable,@{@"coord":@"point",@"width":@(double(INT_MAX)-1)},nil);
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,badTable,@{},code);
    const int wireCalls=calls;auto context=parent();reset(context);NSDictionary *miss=invoke(1,missPoints,@{},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&[miss[@"x"] intValue]==-1&&[miss[@"y"] intValue]==-1&&!miss[@"value"]);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameMultiReads;
    NSDictionary *denied=invoke(1,points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameMultiReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,points,@{},context).value,@"AbortError");assert(frameMultiReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameMultiReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameMultiReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameMultiReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,points,@{},context).value,@"native_exception");}
    for(NSArray *list:@[points,missPoints]){
        context=parent();reset(context);NSDictionary *success=invoke(1,list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,list,@{},context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,list,@{},context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame multi actual bridge/entry passed: 160 frozen JS/RAW ROI/offset/skip cases, aliases/defaults/full table preflight, 512/513 and exact ingress/Unicode/NUL, ROI/table/offset precedence, scalar modes, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
int main() { @autoreleasepool {
    auto bridge = [TLinkInProcessNativeBridge new]; mode = @"echo";
    auto context = parent();
    auto result = [bridge executeRawPayload:@"18xin chào" context:context];
    assert([result[@"ok"] boolValue] && [result[@"parts"][1] isEqualToString:@"xin chào"]);
    assert(observed.cancellationToken == context.cancellationToken && [observed.ownerRunId isEqualToString:@"run"]);
    assert(lastPayload == "18xin chào" && !TLinkCurrentNativeBudget());
    const int initial = calls;
    failure([bridge executeRawPayload:[@"18" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0] context:context], @"input_too_large");
    unichar nul[] = {'1', '8', 0, 'a'};
    failure([bridge executeRawPayload:[NSString stringWithCharacters:nul length:4] context:context], @"invalid_payload");
    assert(calls == initial);
    assert([[bridge executeRawPayload:[@"18" stringByPaddingToLength:8192 withString:@"界" startingAtIndex:0] context:context][@"ok"] boolValue]);
    assert(lastPayload.size() == 2 + 8190 * 3);
    assert([[bridge executeRawPayload:@"18" context:nil][@"ok"] boolValue]);
    mode = @"chunks";
    assert([[bridge executeRawPayload:@"18" context:parent(1, 13)][@"raw"] isEqualToString:@"0;;1234567890"]);
    failure([bridge executeRawPayload:@"18" context:parent(1, 12)], @"response_too_large");
    mode = @"exception";
    failure([bridge executeRawPayload:@"18" context:parent()], @"native_exception");
    assert(!TLinkCurrentNativeBudget());
    mode = @"wait";
    failure([bridge executeRawPayload:@"18" context:parent(0.01)], @"TimeoutError");
    context = parent(); [context.cancellationToken cancel];
    const int beforeCancel = calls;
    failure([bridge executeRawPayload:@"18" context:context], @"AbortError");
    assert(calls == beforeCancel);
    // Cleanup can run after cancellation/deadline; it retains the owner tuple.
    assert([[bridge executeRawPayload:@"6741;;session;;run;;test" context:context][@"ok"] boolValue]);
    for (NSString *payload in @[@"66", @"481;;0;;0;;5;;5", @"482;;/image.png"]) {
        mode = @"cancelAllocation"; const int previous = releases;
        failure([bridge executeRawPayload:payload context:parent()], @"AbortError");
        assert(releases == previous + 1 && lastPayload.find(";;session;;run;;test") != std::string::npos);
        mode = @"expireAllocation";
        failure([bridge executeRawPayload:payload context:parent(0.05)], @"TimeoutError");
        assert(releases == previous + 2);
    }
    const int beforeSmall = calls;
    failure([bridge executeRawPayload:@"66" context:parent(1, 32)], @"response_too_large");
    assert(calls == beforeSmall);
    // Typed shell's explicit deadline survives the nested wire call; parent budget wins.
    context = parent(200);
    auto typed = TLinkNativeCallContext(context, NO, NO, 120);
    auto nested = TLinkNativeCallContext(typed, NO, YES);
    assert([typed nativeBudget]->remainingSeconds(200) > 119);
    assert([nested nativeBudget]->deadline() == [typed nativeBudget]->deadline());
    auto shorter = TLinkNativeCallContext(typed, NO, NO, 300);
    assert([shorter nativeBudget]->deadline() == [typed nativeBudget]->deadline());
    auto rawContext = parent(0, 0);
    [rawContext setNativeBudget:TLinkTaskBudget(rawContext)];
    assert(TLinkTaskBudget(rawContext) == [rawContext nativeBudget]);
    assert([rawContext nativeBudget]->deadline() == 0);
    auto fromRaw = TLinkNativeCallContext(rawContext, NO, YES);
    assert(fromRaw.defaultTimeoutSeconds == 30 && [fromRaw nativeBudget]->deadline() != 0);
    // The actual queue wrapper restores scopes and skips work expired while queued.
    auto queue = dispatch_queue_create("native.budget.test", DISPATCH_QUEUE_SERIAL);
    auto budget = [typed nativeBudget];
    { TLinkNativeBudgetScope scope(budget);
      TLinkNativeDispatchSync(queue, ^{ assert(TLinkCurrentNativeBudget() == budget); }); }
    dispatch_sync(queue, ^{ assert(!TLinkCurrentNativeBudget()); });
    auto blocked = dispatch_semaphore_create(0), gate = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{ dispatch_semaphore_signal(blocked); dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
    dispatch_semaphore_wait(blocked, DISPATCH_TIME_FOREVER);
    auto expired = std::make_shared<TLinkNativeBudget>(nullptr, TLinkNativeDeadline(0.005), 1024);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    dispatch_semaphore_signal(gate);
    { TLinkNativeBudgetScope scope(expired); TLinkNativeDispatchSync(queue, ^{ assert(false && "expired queued operation ran"); }); }
    typedHardwareKeyCases(bridge);
    typedKeepAwakeCases(bridge);
    typedIndicatorCases(bridge);
    checkGesture(zx_handleNativeTap, @"20;;30;;60000;;19", 1, 1);
    checkGesture(zx_handleNativeSwipe, @"20;;30;;80;;90;;5000;;19;;120", 1, 2);
    checkGesture(zx_handleNativeGesture, @"19;;500;;20,30|40,50|60,70", 1, 2);
    checkGesture(zx_handleNativeGesture, @"zoom;;250;;500;;20;;80;;5000;;2;;120", 2, 2);
    checkGesture(zx_handleNativeBatch, @"1011190020000300", 1, 1); // abort after final raw DOWN still releases
    injected.clear(); touchToken = nil; cancelAt = 0;
    { TLinkNativeBudgetScope scope([TLinkNativeCallContext(parent(1), NO, NO) nativeBudget]);
      NSError *error = nil;
      assert(zx_handleNativeTap((UInt8 *)"20;;30;;0;;0", &error) && injected.size() == 2);
      assert(zx_clampTouchCoord(1e30) == 99999); }
    timingCases();
    typedTouchCases(bridge);
    typedBatchCases(bridge);
    typedColorCases(bridge);
    typedColorRangeCases(bridge);
    typedLiveColorsCases(bridge);
    typedLiveMultiCases(bridge);
    typedFrameImageCases(bridge);
    frameOCRResultCases();
    typedFrameOCRCases(bridge);
    typedFrameReleaseCases(bridge);
    typedImageReleaseCases(bridge);
    frameCaptureResultCases();
    typedFrameCaptureCases(bridge);
    imageOpenResultCases();
    typedImageOpenCases(bridge);
    typedImageCaptureCases(bridge);
    typedFramePickCases(bridge);
    typedFramePickManyCases(bridge);
    typedFrameSearchCases(bridge);
    typedFrameColorsCases(bridge);
    typedFrameMultiCases(bridge);
    typedFrontmostCases(bridge);
    typedFrontmostPidCases(bridge);
    typedAppPidCases(bridge);
    typedAppStateCases(bridge);
    typedAppInfoCases(bridge);
    typedAppPathsCases(bridge);
    typedAppKillCases(bridge);
    typedAppOpenCases(bridge);
    typedListBundlesCases(bridge);
    typedOpenUrlCases(bridge);
    typedDeviceInfoCases(bridge);
    typedRadioCases(bridge);
    typedAuxRadioCases(bridge);
    typedOCRLanguagesCases(bridge);
    typedClipboardTextCases(bridge);
    typedToastCases(bridge);
    typedKeyboardNotificationCases(bridge);
    typedClipboardImageCases(bridge);
    typedAlertCases(bridge);
    typedDialogCases(bridge);
    typedPathCases(bridge);
    std::puts("macOS actual bridge/context/sink/queue and gesture cancellation integration passed.");
} }
