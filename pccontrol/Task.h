#ifndef TASK_H
#define TASK_H

#import <Foundation/Foundation.h>

#define TASK_PERFORM_TOUCH 10
#define TASK_PROCESS_BRING_FOREGROUND 11
#define TASK_SHOW_ALERT_BOX 12
#define TASK_RUN_SHELL 13
#define TASK_TOUCH_RECORDING_START 14
#define TASK_TOUCH_RECORDING_STOP 15
#define TASK_CRAZY_TAP 16
#define TASK_RAPID_FIRE_TAP 17
#define TASK_USLEEP 18
#define TASK_PLAY_SCRIPT 19
#define TASK_PLAY_SCRIPT_FORCE_STOP 20
#define TASK_TEMPLATE_MATCH 21
#define TASK_SHOW_TOAST 22
#define TASK_COLOR_PICKER 23
#define TASK_TEXT_INPUT 24
#define TASK_GET_DEVICE_INFO 25
#define TASK_TOUCH_INDICATOR 26
#define TASK_TEXT_RECOGNIZER 27
#define TASK_COLOR_SEARCHER 28
#define TASK_SCREENSHOT 29
#define TASK_HARDWARE_KEY 30
#define TASK_APP_KILL 31
#define TASK_APP_STATE 32
#define TASK_APP_INFO 33
#define TASK_FRONTMOST_APP_ID 34
#define TASK_FRONTMOST_APP_ORIENTATION 35
#define TASK_SET_AUTO_LAUNCH 36
#define TASK_LIST_AUTO_LAUNCH 37
#define TASK_SET_TIMER 38
#define TASK_REMOVE_TIMER 39
#define TASK_KEEP_AWAKE 40
#define TASK_STOP_SCRIPT 41
#define TASK_DIALOG 42
#define TASK_CLEAR_DIALOG 43
#define TASK_ROOT_DIR 44
#define TASK_CURRENT_DIR 45
#define TASK_BOT_PATH 46

// Cache current screenshot frame
#define TASK_SCREEN_KEEP 47

// Image object + find image
#define TASK_IMAGE_OBJECT 48
#define TASK_FIND_IMAGE 49

// App/process info extensions
#define TASK_APP_PID 50
#define TASK_FRONTMOST_PID 51
#define TASK_APP_PATHS 52
#define TASK_LIST_BUNDLES 53

// Open URL / URL scheme
#define TASK_OPEN_URL 54

// Connectivity & network
#define TASK_WIFI 55
#define TASK_BLUETOOTH 56
#define TASK_AIRPLANE 57
#define TASK_CELLULAR_DATA 58
#define TASK_VPN 59

// Hello/status probe
#define TASK_HELLO_STATUS 60

// Touch with delivery ACK: seq;;legacy_touch_payload
#define TASK_PERFORM_TOUCH_ACK 61

// Native high-level touch commands executed inside SpringBoard.
#define TASK_NATIVE_TAP 62
#define TASK_NATIVE_SWIPE 63
#define TASK_NATIVE_GESTURE 64
#define TASK_NATIVE_BATCH 65

// Manual frame lifecycle for cached image/color checks.
#define TASK_FRAME_CAPTURE 66
#define TASK_FRAME_RELEASE 67
#define TASK_FIND_IMAGE_IN_FRAME 68
#define TASK_COLOR_IN_FRAME 69
#define TASK_FRAME_BATCH 70
#define TASK_RUN_SHELL_V2 71


#define TASK_UPDATE_CACHE 90
#define TASK_OCR_TESSERACT_REGION 91

#define TASK_TEST 99

#import "TLinkTaskContext.h"

void processTaskLegacy(UInt8 *buff, CFWriteStreamRef writeStreamRef = NULL);
void processTaskWithContext(UInt8 *buffer, size_t actualLength, CFWriteStreamRef stream, TLinkTaskExecutionContext *context);
void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef = NULL); // routes to processTaskLegacy

static int getTaskType(UInt8* dataArray);

#endif
