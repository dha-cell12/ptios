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
// First mutation per process repairs retained record/evidence metadata from that index.
// Failed recovery blocks the mutation and is attempted again on the next call.
// Required write failures re-enable recovery before a later mutation in this process.
// A pending marker on the held lock inode also forces recovery in another warm process.
// All writers must use this marker protocol; the lock file must never be replaced.
// The index is the commit point; inspect process-local persistence_diagnostics in status.
// Post-commit retirement only unlinks owned per-ID leaves not referenced by retained runs.
// Cleanup errors preserve committed success and are reported through those diagnostics.
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
// Read/lock/format failures return state=error with a fixed error code; counts/runs
// are unknown placeholders. Status never repairs or rewrites the persisted index.
// Index reads admit regular non-symlink files up to 32 MiB before buffer/JSON work;
// encoded index writes share that cap. Record/evidence encoding is unchanged.
FOUNDATION_EXPORT NSDictionary *TLinkRunHistorySnapshot(NSUInteger limit);

#endif
