#include "Task.h"
#include "Touch.h"
#include "Process.h"
#include "AlertBox.h"
#include "Record.h"
#include "Play.h"
#include "SocketServer.h"
#include "ScreenMatch.h"
#include "Toast.h"
#include "ColorPicker.h"
#include "Image.h"
#include "Connectivity.h"
#include "UIKeyboard.h"
#include "DeviceInfo.h"
#include "TouchIndicator/TouchIndicatorWindow.h"
#include "HardwareKey.h"
#include "Scheduler.h"
#include "RuntimeUtils.h"
#import "ScriptPlayer.h"
#import <mach/mach.h>
#include <Foundation/NSDistributedNotificationCenter.h>
#include <TextRecognization/TextRecognizer.h>
#include "UpdateCache.h"
#include "Screen.h"
#include "NSTask.h"

extern CFRunLoopRef recordRunLoop;
extern ScriptPlayer *scriptPlayer;

/*
get task type
*/
static int getTaskType(UInt8* dataArray)
{
	int taskType = 0;
	for (int i = 0; i <= 1; i++)
	{
		taskType += (dataArray[i] - '0')*pow(10, 1-i);
	}
	return taskType;
}

/**
Process Task
*/
void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    //NSLog(@"### com.zjx.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        @autoreleasepool{
            performTouchFromRawData(eventData);
        }
    }
    else if (taskType == TASK_PROCESS_BRING_FOREGROUND) //bring to foreground
    {
        @autoreleasepool{   
            switchProcessForegroundFromRawData(eventData);
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_SHOW_ALERT_BOX)
    {
        @autoreleasepool{   
            NSError *err = nil;
            showAlertBoxFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_USLEEP)
    {
        if (writeStreamRef)
        {
            int usleepTime = 0;
            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.zjx.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.zjx.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
            notifyClient((UInt8*)"0;;Sleep ends\r\n", writeStreamRef); 
        }
        else
        {
            int usleepTime = 0;

            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.zjx.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.zjx.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
        }

    }
    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
            NSTask *task = [[NSTask alloc] init];

            // 设置执行的命令和参数
            [task setLaunchPath:@"/usr/bin/sudo"];
            [task setArguments:@[[NSString stringWithFormat:@"sudo zxtouchb -e \"%s\"", eventData]]];

            // 设置输出管道，如果需要获取命令的输出
            NSPipe *pipe = [NSPipe pipe];
            [task setStandardOutput:pipe];

            // 启动任务
            [task launch];

            // 等待任务完成
            [task waitUntilExit];

            // 如果需要获取命令的输出，可以使用以下代码
            NSFileHandle *fileHandle = [pipe fileHandleForReading];
            NSData *data = [fileHandle readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Command Output:\n%@", output);

//            system([[NSString stringWithFormat:@"sudo zxtouchb -e \"%s\"", eventData] UTF8String]);
            notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_START)
    {
        @autoreleasepool {
            NSError *err = nil;
            startRecording(writeStreamRef, &err);    
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_STOP)
    {
        @autoreleasepool {
            stopRecording(); 
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            playScript((UInt8*)eventData, &err);
            if (err)
            {
                setLastScriptError([err localizedDescription]);
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT_FORCE_STOP)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptPlaying(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEMPLATE_MATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            CGRect result = screenMatchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", 
                result.origin.x, result.origin.y, result.size.width, result.size.height] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SHOW_TOAST)
    {
        @autoreleasepool {
            NSError *err = nil;
            showToastFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_PICKER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSDictionary *rgb = getRGBFromRawData(eventData, &err); 
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n", [rgb[@"red"] intValue], [rgb[@"green"] intValue], [rgb[@"blue"] intValue]] UTF8String], writeStreamRef);
            }
            rgb = nil;
        }
    }
    else if (taskType == TASK_TEXT_INPUT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = inputTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_GET_DEVICE_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *deviceInfo = getDeviceInfoFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", deviceInfo] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_INDICATOR)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleTouchIndicatorTaskWithRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEXT_RECOGNIZER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *text = performTextRecognizerTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", text] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_SEARCHER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *returndata = searchRGBFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", returndata] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HARDWARE_KEY)
    {
        @autoreleasepool {
            NSError *err = nil;
            sendHardwareKeyEventFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_KILL)
    {
        @autoreleasepool {
            NSError *err = nil;
            killAppFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_STATE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = appStateFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *info = appInfoFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", info] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ID)
    {
        @autoreleasepool {
            NSString *frontApp = frontMostAppId();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", frontApp] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ORIENTATION)
    {
        @autoreleasepool {
            NSString *orientation = frontMostAppOrientation();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", orientation] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SET_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            setAutoLaunchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *list = listAutoLaunch(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", list ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SET_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            setTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_REMOVE_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            removeTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_KEEP_AWAKE)
    {
        @autoreleasepool {
            NSError *err = nil;
            keepAwakeFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = appPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = frontMostPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PATHS)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *paths = appPathsFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", paths ?: @";;"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_BUNDLES)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = listBundlesFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OPEN_URL)
    {
        @autoreleasepool {
            NSError *err = nil;
            (void)openUrlFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_WIFI)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = wifiTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_BLUETOOTH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = bluetoothTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_AIRPLANE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = airplaneTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CELLULAR_DATA)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = cellularDataTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_VPN)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = vpnTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HELLO_STATUS)
    {
        @autoreleasepool {
            UIDevice *dev = [UIDevice currentDevice];
            NSString *name = dev.name ?: @"";
            NSString *systemName = dev.systemName ?: @"iOS";
            NSString *systemVersion = dev.systemVersion ?: @"";
            NSString *model = dev.model ?: @"";

            BOOL playing = false;
            NSString *bundlePath = @"";
            if (scriptPlayer) {
                playing = [scriptPlayer isPlaying];
                bundlePath = [scriptPlayer getCurrentBundlePath] ?: @"";
            }

            NSDictionary *payload = @{
                @"zxtouch": @{
                    @"protocols": @[@"v0", @"v1"],
                    @"port": @6000,
                },
                @"device": @{
                    @"name": name,
                    @"system_name": systemName,
                    @"system_version": systemVersion,
                    @"model": model,
                },
                @"script": @{
                    @"is_playing": @(playing),
                    @"bundle_path": bundlePath,
                    @"last_error": getLastScriptError() ?: @"",
                    @"last_error_ts": @(getLastScriptErrorTs()),
                },
            };

            NSError *jsonErr = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
            if (!jsonData || jsonErr) {
                notifyClient((UInt8*)"1;;Failed to encode hello status.\r\n", writeStreamRef);
                return;
            }
            NSString *b64 = [jsonData base64EncodedStringWithOptions:0];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", b64 ?: @""] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREEN_KEEP)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleScreenKeepTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_IMAGE_OBJECT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleImageObjectTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (ret && [ret length] > 0)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_STOP_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptFromRawData(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *response = dialogFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", response ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CLEAR_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            clearDialogValues(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_ROOT_DIR)
    {
        @autoreleasepool {
            NSString *path = rootDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_CURRENT_DIR)
    {
        @autoreleasepool {
            NSString *path = currentDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_BOT_PATH)
    {
        @autoreleasepool {
            NSString *path = botPathValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREENSHOT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *resultPath = handleScreenshotTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (resultPath)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", resultPath] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_UPDATE_CACHE)
    {
        @autoreleasepool{
            NSError *err = nil;
            updateCacheFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[@"0\r\n" UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEST)
    {

    }
}
