- (pid_t)streamdPidFromHelloStatusLocked
{
    NSString *response = [self sendLocalTaskLineLocked:@"60\n" timeout:2];
    if (![response hasPrefix:@"0;;"]) return 0;
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return 0;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return 0;
    return (pid_t)[json[@"pid"] intValue];
}

- (NSString *)streamdLaunchPathFromHelloStatusLocked
{
    NSString *response = [self sendLocalTaskLineLocked:@"60\n" timeout:2];
    if (![response hasPrefix:@"0;;"]) return @"";
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return @"";
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    NSString *path = nil;
    if ([json isKindOfClass:[NSDictionary class]]) path = json[@"launch_executable_path"];
    return [path isKindOfClass:[NSString class]] ? path : @"";
}

- (BOOL)probeTaskServerAndUpdateLocked:(NSString *)reason
{
    NSString *status = [self sendLocalTaskLineLocked:@"97\n" timeout:2];
    if (status.length == 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: %@ probe tcp/6000 no response", reason ?: @"service"]];
        self->_running = NO;
        self->_pid = -1;
        self->_requiresReplacement = NO;
        [self emitRunning:NO pid:-1];
        return NO;
    }

    pid_t pid = [self streamdPidFromHelloStatusLocked];
    BOOL versionMatches =
        [status containsString:kSCRequiredStreamdServiceMarker] &&
        [status containsString:kSCRequiredVPNServiceMarker];
    BOOL pathMatches = YES;
    NSString *runningPath = @"";
    if (pid > 0) {
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
        int pathLength = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));
        if (pathLength > 0) {
            runningPath = [NSString stringWithUTF8String:pathBuffer] ?: @"";
            NSString *expectedPath = [[[self streamdPath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
            NSString *actualPath = [[runningPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
            pathMatches = expectedPath.length > 0 && [actualPath isEqualToString:expectedPath];
        } else {
            // proc_pidpath can fail across the app/root process boundary. The
            // daemon records argv[0] at startup so we can still distinguish a
            // live binary from one in a removed TrollStore container.
            runningPath = [self streamdLaunchPathFromHelloStatusLocked];
            NSString *expectedPath = [[[self streamdPath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
            NSString *actualPath = [[runningPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
            pathMatches = expectedPath.length > 0 && actualPath.length > 0 && [actualPath isEqualToString:expectedPath];
            if (runningPath.length == 0) runningPath = @"unresolvable";
        }
    }
    if (!versionMatches || !pathMatches) {
        self->_running = NO;
        self->_pid = pid > 0 ? pid : -1;
        self->_requiresReplacement = YES;
        [self emitRunning:NO pid:self->_pid];
        [self emitLog:[NSString stringWithFormat:@"supervisor: %@ found stale streamd pid=%d version=%@ path=%@; replacement required",
                       reason ?: @"service",
                       self->_pid,
                       versionMatches ? @"current" : @"outdated",
                       runningPath.length > 0 ? runningPath : @"unknown"]];
        return NO;
    }

    self->_running = YES;
    self->_pid = pid > 0 ? pid : self->_pid;
    self->_requiresReplacement = NO;
    [self emitRunning:YES pid:self->_pid];
    [self emitLog:[NSString stringWithFormat:@"supervisor: %@ probe ok pid=%d -> %@",
                   reason ?: @"service",
                   self->_pid,
                   [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
    return YES;
}

