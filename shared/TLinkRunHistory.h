#ifndef TLINK_RUN_HISTORY_H
#define TLINK_RUN_HISTORY_H

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const TLinkRunHistorySchemaV1;
FOUNDATION_EXPORT NSString * const TLinkFailureEvidenceSchemaV1;

FOUNDATION_EXPORT NSString *TLinkRunHistoryRootPath(void);
FOUNDATION_EXPORT NSString *TLinkRunHistoryRunsPath(void);
FOUNDATION_EXPORT NSString *TLinkRunHistoryEvidencePath(void);

// Begin/finish return an empty dictionary when a required history read/write fails.
// Only a missing index starts empty; unreadable/invalid indexes are preserved.
// The index is the commit point; inspect process-local persistence_diagnostics in status.
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
// Formats one decoded index after releasing the file lock, under the local monitor.
FOUNDATION_EXPORT NSDictionary *TLinkRunHistorySnapshot(NSUInteger limit);

#endif
