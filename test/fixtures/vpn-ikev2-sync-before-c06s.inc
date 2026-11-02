NSDictionary *TLinkVPNConfigureIKEv2SynchronouslyForHelper(
    NSString *serverAddress,
    NSString *remoteIdentifier,
    NSString *username,
    NSString *password)
{
    if (geteuid() != 0) {
        return TLinkVPNResult(false, @"vpn_private_root_helper_required", @{
            @"executor_uid": @(geteuid()),
        });
    }

    __block NSDictionary *completedResult = nil;
    TLinkVPNConfigureIKEv2(
        serverAddress, remoteIdentifier, username, password,
        ^(NSDictionary *result) {
            completedResult = result;
        });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (!completedResult && [deadline timeIntervalSinceNow] > 0.0) {
        @autoreleasepool {
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                   beforeDate:[NSDate
                                       dateWithTimeIntervalSinceNow:0.1]];
        }
    }
    if (!completedResult) {
        return TLinkVPNResult(false,
            @"vpn_ikev2_helper_timeout", @{
                @"executor_uid": @(geteuid()),
            });
    }
    NSMutableDictionary *result = [completedResult mutableCopy];
    result[@"executor_uid"] = @(geteuid());
    result[@"executor_gid"] = @(getegid());
    result[@"execution_process"] = @"privhelper_tsrootbinary";
    if ([result[@"ok"] boolValue]) {
        result[@"approval_path"] =
            @"privhelper_root_nevpnmanager_super_configuration";
    }
    return result;
}

