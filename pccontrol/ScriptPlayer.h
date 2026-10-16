#ifndef SCRIPT_PLAYER_H
#define SCRIPT_PLAYER_H

#import <Foundation/Foundation.h>

@interface ScriptPlayer : NSObject


- (void)setRepeatTime:(int)rt;
- (void)setInterval:(float)intv;
- (void)setSpeed:(float)sp;
- (void)setPath:(NSString*)path;
// Requests cancellation; isPlaying remains YES through worker and history/touch cleanup.
- (void)forceStop:(NSError**)error;
- (void)setSwitchApp:(BOOL)value;

- (id)initWithPath:(NSString*)path;

- (int)play:(NSError**)error;
// Atomically admit a complete launch tuple; busy includes stopping and cleanup.
- (int)playPath:(NSString *)path repeatTime:(int)repeats interval:(double)delay speed:(double)playSpeed
     switchApp:(BOOL)switchApp error:(NSError **)error;
- (BOOL)isPlaying;
- (BOOL)canStartScheduledScript;
- (NSString*)getCurrentBundlePath;
- (NSDictionary *)licenseRuntimeDiagnostics;

@end

#endif
