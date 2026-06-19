#ifndef TLinkauto_IPC_CONSTANTS_H
#define TLinkauto_IPC_CONSTANTS_H

#include <CoreFoundation/CoreFoundation.h>

static CFStringRef const kTLinkautoIPCPortName = CFSTR("com.tlinkauto.tlinkautod.springboard");
static const char *const kTLinkautoIPCCommandHome = "CMD_HOME";
static const char *const kTLinkautoIPCCommandPing = "CMD_PING";
static const char *const kTLinkautoIPCCommandTaskPrefix = "TASK::";
static NSString *const kTLinkautoIPCReadyMarkerPath = @"/var/mobile/Library/TLinkauto/ipc_ready";
static NSString *const kTLinkautoTweakLoadedMarkerPath = @"/var/mobile/Library/TLinkauto/tweak_loaded";

#endif
