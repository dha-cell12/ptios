- (JSValue *)openFile:(NSString *)path mode:(NSString *)mode
{
    JSContext *context = [JSContext currentContext];
    if (!context) return nil;

    NSString *openMode = mode.length > 0 ? mode : @"r";
    if (!TLinkJSFileModeIsValid(openMode)) {
        return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"invalid_file_mode", @"mode": openMode}
                              inContext:context];
    }
    BOOL writing = TLinkJSFileModeWrites(openMode);
    NSDictionary *resolved = [self resolvedOpenFilePath:path writing:writing];
    if (![resolved[@"ok"] boolValue]) return [JSValue valueWithObject:resolved inContext:context];
    NSString *resolvedPath = resolved[@"path"] ?: @"";

    __block NSUInteger handleId = 0;
    @synchronized (self) {
        if (self.openFileHandles.count >= kTLinkautoJSMaxOpenFiles) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"too_many_open_files", @"limit": @(kTLinkautoJSMaxOpenFiles)}
                                      inContext:context];
        }
        handleId = self.nextOpenFileHandleId++;
    }

    NSString *openError = nil;
    TLinkJSFileHandle *handle = [TLinkJSFileHandle openPath:resolvedPath
                                                      mode:openMode
                                                  handleId:handleId
                                          maxTransferBytes:(NSUInteger)kTLinkautoJSMaxStorageFileBytes
                                                     error:&openError];
    if (!handle) {
        return [JSValue valueWithObject:@{@"ok": @NO,
                                          @"error": openError ?: @"file_open_failed",
                                          @"path": resolvedPath,
                                          @"mode": openMode}
                              inContext:context];
    }
    @synchronized (self) {
        self.openFileHandles[@(handleId)] = handle;
    }
    __weak TLinkautoDeviceBridge *weakSelf = self;
    return TLinkJSFileHandleCreateJSObject(context, handle, ^(NSUInteger closedId) {
        TLinkautoDeviceBridge *strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (strongSelf) {
            [strongSelf.openFileHandles removeObjectForKey:@(closedId)];
        }
    });
}

