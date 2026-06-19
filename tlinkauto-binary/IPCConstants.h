#ifndef TLinkautoD_IPC_CONSTANTS_H
#define TLinkautoD_IPC_CONSTANTS_H

#include <CoreFoundation/CoreFoundation.h>

static CFStringRef const kTLinkautoIPCPortName = CFSTR("com.tlinkauto.tlinkautod.springboard");
static const char *const kTLinkautoIPCCommandHome = "CMD_HOME";
static const char *const kTLinkautoIPCCommandPing = "CMD_PING";
static const char *const kTLinkautoIPCCommandTaskPrefix = "TASK::";
static const char *const kTLinkautoIPCReadyMarkerPath = "/var/mobile/Library/TLinkauto/ipc_ready";

#endif
