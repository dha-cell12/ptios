// Frozen 68cd857 listBundles compatibility oracle.
NSString* listBundlesFromRawData(UInt8 *eventData, NSError **error)
{
    // eventData: "1" => with info
    BOOL withInfo = false;
    if (eventData) {
        NSString *raw = [NSString stringWithFormat:@"%s", eventData];
        withInfo = ([raw intValue] == 1);
    }

    Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsCls || ![wsCls respondsToSelector:@selector(defaultWorkspace)]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;LSApplicationWorkspace unavailable.\r\n"}];
        }
        return nil;
    }
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsCls, @selector(defaultWorkspace));
    if (!ws) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to get LSApplicationWorkspace.\r\n"}];
        }
        return nil;
    }

    NSArray *apps = nil;
    SEL allInstalledSel = NSSelectorFromString(@"allInstalledApplications");
    SEL allSel = NSSelectorFromString(@"allApplications");
    if ([ws respondsToSelector:allInstalledSel]) {
        apps = ((NSArray *(*)(id, SEL))objc_msgSend)(ws, allInstalledSel);
    } else if ([ws respondsToSelector:allSel]) {
        apps = ((NSArray *(*)(id, SEL))objc_msgSend)(ws, allSel);
    }
    if (!apps) {
        apps = @[];
    }

    if (!withInfo) {
        NSMutableArray<NSString *> *bids = [NSMutableArray arrayWithCapacity:[apps count]];
        for (id p in apps) {
            NSString *bid = nil;
            if ([p respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
                bid = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleIdentifier"));
            } else {
                @try { bid = [p valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
            }
            if (bid && [bid length] > 0) {
                [bids addObject:bid];
            }
        }
        return [bids componentsJoinedByString:@",,"];
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:[apps count]];
    for (id p in apps) {
        NSString *bid = nil;
        if ([p respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
            bid = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleIdentifier"));
        } else {
            @try { bid = [p valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
        }
        if (!bid || [bid length] == 0) {
            continue;
        }

        NSString *name = @"";
        NSString *shortVersion = @"";
        NSString *bundleVersion = @"";
        if ([p respondsToSelector:NSSelectorFromString(@"localizedName")]) {
            name = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"localizedName")) ?: @"";
        } else {
            @try { name = zx_safeString([p valueForKey:@"localizedName"]); } @catch (__unused NSException *e) {}
        }
        if ([p respondsToSelector:NSSelectorFromString(@"shortVersionString")]) {
            shortVersion = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"shortVersionString")) ?: @"";
        } else {
            @try { shortVersion = zx_safeString([p valueForKey:@"shortVersionString"]); } @catch (__unused NSException *e) {}
        }
        if ([p respondsToSelector:NSSelectorFromString(@"bundleVersion")]) {
            bundleVersion = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleVersion")) ?: @"";
        } else {
            @try { bundleVersion = zx_safeString([p valueForKey:@"bundleVersion"]); } @catch (__unused NSException *e) {}
        }

        [items addObject:@{
            @"bundle_id": bid,
            @"name": name ?: @"",
            @"short_version": shortVersion ?: @"",
            @"bundle_version": bundleVersion ?: @"",
        }];
    }

    NSDictionary *obj = @{@"items": items};
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&jsonErr];
    if (!jsonData || jsonErr) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to encode bundles JSON.\r\n"}];
        }
        return nil;
    }
    return [jsonData base64EncodedStringWithOptions:0];
}

