#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TLinkAdaptiveStreamingSchemaV1;

FOUNDATION_EXPORT NSDictionary *TLinkAdaptiveStreamingSubmitFeedback(NSString *runtime,
                                                                      NSString *_Nullable base64Body,
                                                                      NSString *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *TLinkAdaptiveStreamingDecision(NSString *runtime,
                                                                NSInteger port,
                                                                NSInteger baseFPS,
                                                                NSInteger minimumFPS,
                                                                NSInteger baseBitrate,
                                                                NSInteger thermalFPS,
                                                                NSInteger thermalBitrate);
FOUNDATION_EXPORT void TLinkAdaptiveStreamingSessionStarted(NSString *runtime,
                                                            NSInteger port,
                                                            NSString *profile,
                                                            NSInteger width,
                                                            NSInteger height,
                                                            NSInteger baseFPS,
                                                            NSInteger baseBitrate);
FOUNDATION_EXPORT void TLinkAdaptiveStreamingSessionEnded(NSString *runtime,
                                                          NSInteger port,
                                                          NSString *reason);
FOUNDATION_EXPORT void TLinkAdaptiveStreamingRecordRecovery(NSString *runtime,
                                                            NSInteger port,
                                                            NSString *reason,
                                                            BOOL succeeded);
FOUNDATION_EXPORT NSDictionary *TLinkAdaptiveStreamingStatus(NSString *runtime);

FOUNDATION_EXPORT void TLinkAdaptiveStreamingSessionStartedForSession(NSString *runtime, NSInteger port, NSString *profile,
    NSInteger width, NSInteger height, NSInteger baseFPS, NSInteger baseBitrate, NSString *sessionID);
FOUNDATION_EXPORT void TLinkAdaptiveStreamingSessionEndedForSession(NSString *runtime, NSInteger port, NSString *reason, NSString *sessionID);
FOUNDATION_EXPORT NSDictionary *TLinkAdaptiveStreamingDecisionForSession(NSString *runtime, NSInteger port, NSInteger baseFPS,
    NSInteger minimumFPS, NSInteger baseBitrate, NSInteger thermalFPS, NSInteger thermalBitrate, NSString *sessionID);

// Numeric snapshot on the capture thread; at most one decision refresh per process.
@interface TLinkAdaptiveStreamingSampler : NSObject
- (instancetype)initWithFPS:(int)fps minimumFPS:(int)minimumFPS bitrate:(int)bitrate decision:(NSDictionary *(^)(void))decision;
- (void)readTargetFPS:(int *)fps bitrate:(int *)bitrate;
- (void)invalidate;
@end
FOUNDATION_EXPORT void TLinkAdaptiveStreamingRecordRecoveryAsync(NSString *runtime, NSInteger port, NSString *reason, BOOL succeeded);

NS_ASSUME_NONNULL_END
