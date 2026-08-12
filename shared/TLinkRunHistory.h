#ifndef TLINK_RUN_HISTORY_H
#define TLINK_RUN_HISTORY_H

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const TLinkRunHistorySchemaV1;
FOUNDATION_EXPORT NSString * const TLinkFailureEvidenceSchemaV1;

FOUNDATION_EXPORT NSString *TLinkRunHistoryRootPath(void);
FOUNDATION_EXPORT NSString *TLinkRunHistoryRunsPath(void);
FOUNDATION_EXPORT NSString *TLinkRunHistoryEvidencePath(void);

FOUNDATION_EXPORT NSDictionary *TLinkRunHistoryBegin(NSString *runtime,
                                                     NSString *bundlePath,
                                                     NSString *entryPath,
                                                     NSDictionary *playSettings);
FOUNDATION_EXPORT NSDictionary *TLinkRunHistoryFinish(NSString *runId,
                                                      NSString *state,
                                                      NSString *error,
                                                      NSArray<NSString *> *logTail,
                                                      NSString *consoleLogPath,
                                                      NSString *screenshotPath,
                                                      NSString *screenshotError,
                                                      NSDictionary *extra);
FOUNDATION_EXPORT NSDictionary *TLinkRunHistorySnapshot(NSUInteger limit);

#endif
