- (JSValue *)openFileAtRelativePath:(NSString *)relativePath
                               mode:(NSString *)mode
                         bundlePath:(NSString *)bundlePath
                            context:(JSContext *)context
                          sessionId:(NSString *)sessionId
{
    self.storageOpsCount++;
    NSString *openMode = mode.length > 0 ? mode : @"r";
    if (!TLinkJSFileModeIsValid(openMode)) {
        return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"invalid_file_mode", @"mode": openMode} inContext:context];
    }
    BOOL writing = TLinkJSFileModeWrites(openMode);
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath
                                                          bundlePath:bundlePath
                                                             writing:writing
                                                        createParent:writing];
    if (![resolved[@"ok"] boolValue]) return [JSValue valueWithObject:resolved inContext:context];
    NSString *path = resolved[@"path"] ?: @"";

    __block NSUInteger handleId = 0;
    @synchronized (self) {
        if (self.activeFileHandles.count >= kTLinkJSHelperMaxOpenFiles) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"too_many_open_files", @"limit": @(kTLinkJSHelperMaxOpenFiles)} inContext:context];
        }
        handleId = self.nextFileHandleId++;
    }
    NSString *openError = nil;
    TLinkJSFileHandle *handle = [TLinkJSFileHandle openPath:path
                                                      mode:openMode
                                                  handleId:handleId
                                          maxTransferBytes:(NSUInteger)kTLinkJSHelperMaxStorageFileBytes
                                                     error:&openError];
    if (!handle) {
        return [JSValue valueWithObject:@{@"ok": @NO, @"error": openError ?: @"file_open_failed", @"path": path, @"mode": openMode} inContext:context];
    }
    @synchronized (self) {
        self.activeFileHandles[@(handleId)] = handle;
    }
    __weak TLinkJSHelperServer *weakSelf = self;
    NSString *ownerSessionId = [sessionId copy];
    return TLinkJSFileHandleCreateJSObject(context, handle, ^(NSUInteger closedId) {
        TLinkJSHelperServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.rpcCondition lock];
        @try {
            if (![strongSelf.activeSessionId isEqualToString:ownerSessionId]) return;
            @synchronized (strongSelf) {[strongSelf.activeFileHandles removeObjectForKey:@(closedId)];}
        } @finally {[strongSelf.rpcCondition unlock];}
    });
}

