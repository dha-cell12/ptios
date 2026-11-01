- (void)updateDiagnostics:(NSDictionary *)values refreshHistoryEvent:(NSDictionary *)event
{
    if (values.count == 0 && event.count == 0) return;
    @synchronized (self) {
        NSString *directory = [kTLinkLicenseLifecycleDiagnosticsPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath] mutableCopy];
        if (!state) state = [NSMutableDictionary dictionary];
        if (event.count > 0) {
            NSArray *stored = [state[@"refresh_history"] isKindOfClass:[NSArray class]] ? state[@"refresh_history"] : @[];
            NSMutableArray *history = [stored mutableCopy];
            [history addObject:event];
            if (history.count > kTLinkLicenseRefreshHistoryLimit) {
                NSRange overflow = NSMakeRange(0, history.count - kTLinkLicenseRefreshHistoryLimit);
                [history removeObjectsInRange:overflow];
            }
            state[@"refresh_history"] = history;
        }
        if (values.count > 0) [state addEntriesFromDictionary:values];
        state[@"mode"] = @"foreground_bg_single_flight_backoff_v1";
        state[@"updated_at_ms"] = @([self nowMilliseconds]);
        [state writeToFile:kTLinkLicenseLifecycleDiagnosticsPath atomically:YES];
    }
}

- (void)recordRefreshFailure:(NSString *)message trigger:(NSString *)trigger historyEvent:(NSDictionary *)event
{
    @synchronized (self) {
        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath];
        NSInteger failures = MIN(16, [existing[@"consecutive_failures"] integerValue] + 1);
        NSInteger exponent = MIN(8, failures - 1);
        NSTimeInterval delay = MIN(kTLinkLicenseBackoffMaximum,
                                   kTLinkLicenseBackoffBase * pow(2.0, (double)exponent));
        uint32_t jitterValue = arc4random_uniform(4001);
        double jitter = 0.8 + ((double)jitterValue / 10000.0);
        uint64_t nextAttempt = [self nowMilliseconds] + (uint64_t)(delay * jitter * 1000.0);
        [self updateDiagnostics:@{
            @"last_result": @"failed",
            @"last_error": message ?: @"license_refresh_failed",
            @"last_trigger": trigger ?: @"unknown",
            @"consecutive_failures": @(failures),
            @"next_attempt_at_ms": @(nextAttempt),
        } refreshHistoryEvent:event];
    }
}

