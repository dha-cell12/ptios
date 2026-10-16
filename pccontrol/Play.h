#ifndef PLAY_H
#define PLAY_H

#import <Foundation/Foundation.h>

// Cheap admission snapshot; actual launch still rechecks player state.
BOOL canStartScriptPlaying(void);
int playScript(UInt8* path, NSError** error);
void playFromRawFile(NSString* filePath, NSString* foregroundApp, NSError **err);
void stopScriptPlaying(NSError **error);
void playHasStoppedCallBack();
void initScriptPlayer();

#endif
