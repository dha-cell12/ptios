JSValue *TLinkJSFileHandleCreateJSObject(JSContext *context,
                                         TLinkJSFileHandle *handle,
                                         void (^didClose)(NSUInteger handleId))
{
    JSValue *object = [JSValue valueWithNewObjectInContext:context];
    object[@"ok"] = @YES;
    object[@"id"] = @(handle.handleId);
    object[@"path"] = handle.path ?: @"";
    object[@"mode"] = handle.mode ?: @"r";
    object[@"read"] = ^NSDictionary *(JSValue *request) {
        id value = (!request || [request isUndefined] || [request isNull]) ? @"*a" : [request toObject];
        return [handle readRequest:value];
    };
    object[@"readLine"] = ^NSDictionary *{ return [handle readLine]; };
    object[@"write"] = ^NSDictionary *(JSValue *value) { return [handle writeText:[value toString] ?: @""]; };
    object[@"writeBase64"] = ^NSDictionary *(NSString *base64) { return [handle writeBase64:base64 ?: @""]; };
    object[@"seek"] = ^NSDictionary *(NSString *whence, double offset) {
        return [handle seekWhence:whence ?: @"set" offset:(long long)offset];
    };
    object[@"tell"] = ^NSDictionary *{ return [handle tell]; };
    object[@"flush"] = ^NSDictionary *{ return [handle flush]; };
    object[@"isClosed"] = ^BOOL { return handle.isClosed; };
    object[@"close"] = ^NSDictionary *{
        NSDictionary *result = [handle close];
        if (didClose) didClose(handle.handleId);
        return result;
    };
    return object;
}
