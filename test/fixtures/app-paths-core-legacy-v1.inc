// Frozen aca0719 app paths compatibility oracle.
NSString* appPathsFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    if (!proxy) {
        return @";;";
    }

    id bundleURL = nil;
    if ([proxy respondsToSelector:NSSelectorFromString(@"bundleURL")]) {
        bundleURL = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleURL"));
    } else {
        @try { bundleURL = [proxy valueForKey:@"bundleURL"]; } @catch (__unused NSException *e) {}
    }
    NSString *bundlePath = zx_pathFromURLLike(bundleURL);

    id dataURL = nil;
    if ([proxy respondsToSelector:NSSelectorFromString(@"dataContainerURL")]) {
        dataURL = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"dataContainerURL"));
    } else {
        @try { dataURL = [proxy valueForKey:@"dataContainerURL"]; } @catch (__unused NSException *e) {}
        if (!dataURL) {
            @try { dataURL = [proxy valueForKey:@"containerURL"]; } @catch (__unused NSException *e) {}
        }
    }
    NSString *dataPath = zx_pathFromURLLike(dataURL);

    return [NSString stringWithFormat:@"%@;;%@", bundlePath ?: @"", dataPath ?: @""];
}

