static NSDictionary *TLinkScriptStatusDictionary(void)
{
    TLinkScriptSession *session = sTLinkScriptSession;
    if (!session) {
        return @{
            @"is_playing": @(NO),
            @"bundle_path": kTLinkScriptsRootPath,
            @"session_id": @"",
            @"state": @"idle",
            @"last_error": sTLinkLastScriptError ?: @"",
            @"last_error_ts": @(sTLinkLastScriptErrorTs),
            @"log_tail": @[],
        };
    }
    @synchronized (session) {
        BOOL active = TLinkScriptIsActive(session);
        NSUInteger start = session.logs.count > 20 ? session.logs.count - 20 : 0;
        NSArray *tail = session.logs.count > 0 ? [session.logs subarrayWithRange:NSMakeRange(start, session.logs.count - start)] : @[];
        return @{
            @"is_playing": @(active),
            @"bundle_path": kTLinkScriptsRootPath,
            @"session_id": session.sessionId ?: @"",
            @"state": session.state ?: @"idle",
            @"entry_path": session.entryPath ?: @"",
            @"started_at_ms": @(session.startedAtMs),
            @"ended_at_ms": @(session.endedAtMs),
            @"current_run": @(session.currentRun),
            @"total_runs": @(session.totalRuns),
            @"play_settings": @{
                @"repeat_times": @(session.repeatTimes),
                @"interval": @(session.intervalSeconds),
                @"speed": @(session.speed),
            },
            @"last_error": session.lastError.length > 0 ? session.lastError : (sTLinkLastScriptError ?: @""),
            @"license_revoked": @(session.licenseRevoked),
            @"license_revocation_error": session.licenseRevocationError ?: @"",
            @"last_license_check_at_ms": @(session.lastLicenseCheckAtMs),
            @"last_error_ts": @(sTLinkLastScriptErrorTs),
            @"log_tail": tail,
        };
    }
}
