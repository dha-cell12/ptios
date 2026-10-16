#include "Play.h"
#include "SocketServer.h"
#include "Process.h"
#include "Task.h"
#include "AlertBox.h"
#include "Config.h"
#import "ScriptPlayer.h"
#include "Common.h"

#include <atomic>
static std::atomic_bool switchAppBeforeRunScript{true};
ScriptPlayer *scriptPlayer;

void initScriptPlayer()
{
    scriptPlayer = [[ScriptPlayer alloc] init];
}

void updateSwtichAppBeforeRunScript(BOOL value)
{
    switchAppBeforeRunScript = value;
}

BOOL canStartScriptPlaying(void)
{
    return scriptPlayer && [scriptPlayer canStartScheduledScript];
}

int playScript(UInt8* path, NSError **error)
{
    if (!scriptPlayer)
    {
        NSLog(@"com.tlinkauto.springboard: Unable to run the script. Internal error. scriptPlayer is null.");
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Internal error. scriptPlayer is null.\r\n"}];
        return -1;
    }
    // read config file to get repeat time etc
    int repeatTime = 0;
    float sleepBetweenRun = 0;
    float playSpeed = 1.0f;
    
    NSLog(@"com.tlinkauto.springboard: path: %s", path);
    NSMutableDictionary *config;
    if ([[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_PLAY_CONFIG_PATH])
    {
        config = [[NSMutableDictionary alloc] initWithContentsOfFile:SCRIPT_PLAY_CONFIG_PATH];
        NSMutableDictionary *individualConfigs = [config valueForKey:@"individual_configs"];
        if (individualConfigs != nil)
        {
            NSMutableDictionary *scriptPlaybackInfo = [individualConfigs valueForKey:[NSString stringWithFormat:@"%s",path]];
            if (scriptPlaybackInfo != nil)
            {
                repeatTime = [scriptPlaybackInfo[@"repeat_times"] intValue];
                sleepBetweenRun = [scriptPlaybackInfo[@"interval"] floatValue];
                playSpeed = [scriptPlaybackInfo[@"speed"] floatValue];
            }
        }
    }
    

    return [scriptPlayer playPath:[NSString stringWithFormat:@"%s", path]
                      repeatTime:repeatTime interval:sleepBetweenRun speed:playSpeed
                       switchApp:switchAppBeforeRunScript.load() error:error];
}


void stopScriptPlaying(NSError **error)
{
    [scriptPlayer forceStop:error];
}
