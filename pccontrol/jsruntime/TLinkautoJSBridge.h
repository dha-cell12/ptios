#ifndef TLINKAUTO_JS_BRIDGE_H
#define TLINKAUTO_JS_BRIDGE_H

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@class TLinkautoJSRuntimeExecution;

@protocol TLinkautoDeviceJSExport <JSExport>

JSExportAs(tap,
- (NSDictionary *)tap:(double)x y:(double)y);
JSExportAs(swipe,
- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration);
JSExportAs(longPress,
- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration);
JSExportAs(gesture,
- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(runTask,
- (NSDictionary *)runTask:(int)task payload:(NSString *)payload);
JSExportAs(toast,
- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options);
JSExportAs(pickColor,
- (NSDictionary *)pickColor:(double)x y:(double)y);
JSExportAs(screenshotTo,
- (NSDictionary *)screenshotTo:(NSString *)path);
JSExportAs(screenshotRegion,
- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options);
JSExportAs(batch,
- (NSDictionary *)batch:(NSArray *)commands);
JSExportAs(captureFrame,
- (NSDictionary *)captureFrame:(NSDictionary *)options);
JSExportAs(releaseFrame,
- (NSDictionary *)releaseFrame:(int)frameId);
JSExportAs(openImage,
- (NSDictionary *)openImage:(NSString *)path);
JSExportAs(captureImage,
- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height);
JSExportAs(releaseImage,
- (NSDictionary *)releaseImage:(int)imageId);
JSExportAs(framePickColor,
- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options);
JSExportAs(framePickColors,
- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(findImageInFrame,
- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options);
JSExportAs(ocrFrame,
- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options);
JSExportAs(ocr,
- (NSDictionary *)ocr:(NSDictionary *)options);
JSExportAs(openApp,
- (NSDictionary *)openApp:(NSString *)bundleId);
JSExportAs(killApp,
- (NSDictionary *)killApp:(NSString *)bundleId);
JSExportAs(appState,
- (NSDictionary *)appState:(NSString *)bundleId);
JSExportAs(appInfo,
- (NSDictionary *)appInfo:(NSString *)bundleId);
JSExportAs(appPid,
- (NSDictionary *)appPid:(NSString *)bundleId);
JSExportAs(appPaths,
- (NSDictionary *)appPaths:(NSString *)bundleId);
JSExportAs(listBundles,
- (NSDictionary *)listBundles:(BOOL)withInfo);
JSExportAs(openUrl,
- (NSDictionary *)openUrl:(NSString *)url);
JSExportAs(setWifi,
- (NSDictionary *)setWifi:(BOOL)enabled);
JSExportAs(setBluetooth,
- (NSDictionary *)setBluetooth:(BOOL)enabled);
JSExportAs(setAirplaneMode,
- (NSDictionary *)setAirplaneMode:(BOOL)enabled);
JSExportAs(setCellularData,
- (NSDictionary *)setCellularData:(BOOL)enabled);
JSExportAs(alert,
- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration);
JSExportAs(dialog,
- (NSDictionary *)dialog:(NSDictionary *)options);
JSExportAs(setClipboardText,
- (NSDictionary *)setClipboardText:(NSString *)text);
JSExportAs(insertText,
- (NSDictionary *)insertText:(NSString *)text);
JSExportAs(deleteCharacters,
- (NSDictionary *)deleteCharacters:(int)count);
JSExportAs(moveCursor,
- (NSDictionary *)moveCursor:(int)offset);
JSExportAs(hardwareKey,
- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action);
JSExportAs(pressHardwareKey,
- (NSDictionary *)pressHardwareKey:(NSString *)key);
JSExportAs(keepAwake,
- (NSDictionary *)keepAwake:(BOOL)enabled);
JSExportAs(touchIndicator,
- (NSDictionary *)touchIndicator:(NSString *)action);
JSExportAs(runShell,
- (NSDictionary *)runShell:(NSString *)command);
JSExportAs(saveScreenshotToAlbum,
- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path);
JSExportAs(matchTemplate,
- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options);
JSExportAs(findColor,
- (NSDictionary *)findColor:(NSDictionary *)options);
JSExportAs(isColors,
- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(findMultiColor,
- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(setAutoLaunch,
- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled);
JSExportAs(setTimer,
- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script);
JSExportAs(removeTimer,
- (NSDictionary *)removeTimer:(NSString *)name);
JSExportAs(readText,
- (NSDictionary *)readText:(NSString *)path);
JSExportAs(writeText,
- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text);
JSExportAs(readJSON,
- (NSDictionary *)readJSON:(NSString *)path);
JSExportAs(writeJSON,
- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value);
JSExportAs(fileExists,
- (NSDictionary *)fileExists:(NSString *)path);
JSExportAs(deleteFile,
- (NSDictionary *)deleteFile:(NSString *)path);
- (NSDictionary *)getScreenSize;
- (NSDictionary *)screenshot;
- (NSDictionary *)releaseAllFrames;
- (NSDictionary *)info;
- (NSDictionary *)batteryInfo;
- (NSDictionary *)clearScreenshotAlbum;
- (NSDictionary *)listAutoLaunch;
- (NSDictionary *)ocrLanguages;
- (NSDictionary *)clearDialogValues;
- (NSDictionary *)getClipboardText;
- (NSDictionary *)pasteFromClipboard;
- (NSDictionary *)showKeyboard;
- (NSDictionary *)hideKeyboard;
- (NSDictionary *)rootDir;
- (NSDictionary *)currentDir;
- (NSDictionary *)botPath;
- (NSDictionary *)frontMostPid;
- (NSDictionary *)wifi;
- (NSDictionary *)bluetooth;
- (NSDictionary *)airplaneMode;
- (NSDictionary *)cellularData;
- (NSDictionary *)frontMostAppId;
- (NSDictionary *)orientation;
- (NSDictionary *)runtimeInfo;

@end

@interface TLinkautoJSBridge : NSObject <TLinkautoDeviceJSExport>

- (instancetype)initWithExecution:(TLinkautoJSRuntimeExecution *)execution;
- (void)injectIntoContext:(JSContext *)context;

@end

#endif
