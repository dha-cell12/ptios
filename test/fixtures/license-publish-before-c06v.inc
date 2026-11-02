- (void)publishLicenseChange:(NSString *)reason
{
    TLinkLicenseInvalidateCache();
    [self refreshLicenseUISnapshotAsyncForReason:reason ?: @"license_change"];
    uint64_t generation = TLinkLicenseGeneration();
    [self updateDiagnostics:@{
        @"last_change_at_ms": @([self nowMilliseconds]),
        @"last_change_reason": reason ?: @"unknown",
        @"license_generation": @(generation),
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCLicenseLifecycleDidChangeNotification
                                                            object:self
                                                          userInfo:@{@"reason": reason ?: @"unknown"}];
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = SCLicenseRequestDaemonReload();
        [self updateDiagnostics:@{
            @"streamd_invalidate_at_ms": @([self nowMilliseconds]),
            @"streamd_invalidate_response": response ?: @"no_response",
        }];
        if (![response hasPrefix:@"0;;"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *retry = SCLicenseRequestDaemonReload();
                [self updateDiagnostics:@{
                    @"streamd_invalidate_retry_at_ms": @([self nowMilliseconds]),
                    @"streamd_invalidate_retry_response": retry ?: @"no_response",
                }];
            });
        }
    });
}

