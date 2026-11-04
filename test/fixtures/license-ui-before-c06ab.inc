- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason
{
    @synchronized (self) {
        if (self.uiSnapshotRefreshInFlight) {
            self.uiSnapshotRefreshPending = YES;
            self.uiSnapshotPendingReason = reason ?: @"coalesced_change";
            return;
        }
        self.uiSnapshotRefreshInFlight = YES;
    }
    dispatch_async(self.uiSnapshotQueue, ^{
        CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
        NSMutableDictionary *snapshot = [TLinkLicenseStatusDictionary() mutableCopy];
        if (!snapshot) snapshot = [NSMutableDictionary dictionary];
        double elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0;
        snapshot[@"snapshot_ready"] = @YES;
        snapshot[@"snapshot_reason"] = reason ?: @"unspecified";
        snapshot[@"snapshot_created_at_ms"] = @([self nowMilliseconds]);
        snapshot[@"snapshot_refresh_ms"] = @(elapsedMs);
        snapshot[@"source"] = @"rootfull_ui_memory_snapshot";

        __block NSString *pendingReason = nil;
        @synchronized (self) {
            self.uiLicenseSnapshot = [snapshot copy];
            self.uiSnapshotRefreshCount++;
            self.uiSnapshotLastRefreshMs = elapsedMs;
            self.uiSnapshotMaxRefreshMs = MAX(self.uiSnapshotMaxRefreshMs, elapsedMs);
            self.uiSnapshotRefreshInFlight = NO;
            if (self.uiSnapshotRefreshPending) {
                pendingReason = self.uiSnapshotPendingReason ?: @"coalesced_change";
                self.uiSnapshotRefreshPending = NO;
                self.uiSnapshotPendingReason = nil;
            }
        }
        [self updateDiagnostics:@{
            @"ui_snapshot_policy": @"background_generation_driven_v1",
            @"ui_snapshot_refresh_count": @(self.uiSnapshotRefreshCount),
            @"ui_snapshot_last_refresh_ms": @(elapsedMs),
            @"ui_snapshot_max_refresh_ms": @(self.uiSnapshotMaxRefreshMs),
            @"ui_snapshot_generation": snapshot[@"license_generation"] ?: @0,
            @"ui_snapshot_reason": reason ?: @"unspecified",
            @"verifier_performance": TLinkLicensePerformanceDictionary(),
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:SCLicenseLifecycleDidChangeNotification
                              object:self
                            userInfo:@{@"reason": @"ui_snapshot_updated"}];
        });
        if (pendingReason.length > 0) {
            [self refreshLicenseUISnapshotAsyncForReason:pendingReason];
        }
    });
}

