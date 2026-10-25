// Frozen pre-C02b17 action-3 parser/handler at d2c9343; other actions omitted; %s pointer type cast only.
NSString* legacyImageReleaseTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", (const char *)eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image task missing action.\r\n"}];
        }
        return nil;
    }
    int action = [data[0] intValue];
    if (action == 3) {
        if ([data count] < 2) {
            return nil;
        }
        NSString *target = [data[1] isKindOfClass:[NSString class]] ? data[1] : @"";
        NSString *lower = [target lowercaseString];
        __block NSUInteger removed = 0;
        TLinkNativeDispatchSync(zx_imageQueue(), ^{
            if ([lower isEqualToString:@"all"]) {
                if ([data count] >= 5) {
                    std::string sessionId = zx_stringFromPart(data, 2, "");
                    std::string runId = zx_stringFromPart(data, 3, "");
                    std::string runtime = zx_stringFromPart(data, 4, "");
                    std::vector<uint32_t> ids;
                    for (auto const &kv : gImageStore) {
                        if (zx_ownerMatchesImage(*kv.second, sessionId, runId, runtime)) ids.push_back(kv.first);
                    }
                    for (uint32_t iid : ids) {
                        removed += gImageStore.erase(iid);
                    }
                } else {
                    removed = gImageStore.size();
                    gImageStore.clear();
                }
            } else if ([lower isEqualToString:@"scoped"]) {
                if ([data count] >= 5) {
                    std::string sessionId = zx_stringFromPart(data, 2, "");
                    std::string runId = zx_stringFromPart(data, 3, "");
                    std::string runtime = zx_stringFromPart(data, 4, "");
                    std::vector<uint32_t> ids;
                    for (auto const &kv : gImageStore) {
                        if (zx_ownerMatchesImage(*kv.second, sessionId, runId, runtime)) ids.push_back(kv.first);
                    }
                    for (uint32_t iid : ids) {
                        removed += gImageStore.erase(iid);
                    }
                }
            } else {
                uint32_t imageId = (uint32_t)[target intValue];
                auto it = gImageStore.find(imageId);
                if (it != gImageStore.end()) {
                    bool allowed = true;
                    if ([data count] >= 5) {
                        allowed = zx_ownerMatchesImage(*it->second,
                                                       zx_stringFromPart(data, 2, ""),
                                                       zx_stringFromPart(data, 3, ""),
                                                       zx_stringFromPart(data, 4, ""));
                    }
                    if (allowed) {
                        removed = gImageStore.erase(imageId);
                    }
                }
            }
        });
        return [NSString stringWithFormat:@"%lu", (unsigned long)removed];
    }

    return nil;
}
