    device[@"openFile"] = ^JSValue *(NSString *relativePath, NSString *mode) {
        JSContext *currentContext = [JSContext currentContext] ?: context;
        TLinkScriptSession *strongSession = weakSession;
        NSString *openMode = mode.length > 0 ? mode : @"r";
        if (!strongSession) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"script_session_unavailable"} inContext:currentContext];
        }
        if (!TLinkJSFileModeIsValid(openMode)) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"invalid_file_mode", @"mode": openMode} inContext:currentContext];
        }
        BOOL writing = TLinkJSFileModeWrites(openMode);
        NSString *pathError = nil;
        NSString *path = TLinkScriptStoragePath(strongSession, relativePath, writing, &pathError);
        if (!path) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": pathError ?: @"storage_path_error", @"path": relativePath ?: @""} inContext:currentContext];
        }
        if (writing) {
            NSError *mkdirError = nil;
            NSString *parent = [path stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&mkdirError]) {
                return [JSValue valueWithObject:@{@"ok": @NO, @"error": mkdirError.localizedDescription ?: @"create_parent_failed", @"path": path} inContext:currentContext];
            }
        }

        __block NSUInteger handleId = 0;
        @synchronized (strongSession) {
            if (!strongSession.fileHandles) strongSession.fileHandles = [NSMutableDictionary dictionary];
            if (strongSession.fileHandles.count >= kTLinkScriptMaxOpenFiles) {
                return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"too_many_open_files", @"limit": @(kTLinkScriptMaxOpenFiles)} inContext:currentContext];
            }
            handleId = strongSession.nextFileHandleId++;
        }
        NSString *openError = nil;
        TLinkJSFileHandle *handle = [TLinkJSFileHandle openPath:path
                                                          mode:openMode
                                                      handleId:handleId
                                              maxTransferBytes:kTLinkScriptMaxFileTransferBytes
                                                         error:&openError];
        if (!handle) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": openError ?: @"file_open_failed", @"path": path, @"mode": openMode} inContext:currentContext];
        }
        @synchronized (strongSession) {
            strongSession.fileHandles[@(handleId)] = handle;
        }
        __weak TLinkScriptSession *closeSession = strongSession;
        return TLinkJSFileHandleCreateJSObject(currentContext, handle, ^(NSUInteger closedId) {
            TLinkScriptSession *sessionForClose = closeSession;
            if (!sessionForClose) return;
            @synchronized (sessionForClose) {
                [sessionForClose.fileHandles removeObjectForKey:@(closedId)];
            }
        });
    };
