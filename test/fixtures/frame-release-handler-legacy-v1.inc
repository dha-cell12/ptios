// Frozen pre-C02b16 handler at e9e0b1c; function name isolated.
NSString* legacyFrameReleaseTaskFromRawData(UInt8 *eventData, NSError **error)
{
    (void)error;
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *data = [raw componentsSeparatedByString:@";;"];
    NSString *command = [data count] > 0 ? data[0] : @"";
    NSString *lower = [command lowercaseString];
    __block NSUInteger removed = 0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        if ([lower isEqualToString:@"all"]) {
            if ([data count] >= 4) {
                std::string sessionId = zx_stringFromPart(data, 1, "");
                std::string runId = zx_stringFromPart(data, 2, "");
                std::string runtime = zx_stringFromPart(data, 3, "");
                std::vector<uint32_t> ids;
                for (auto const &kv : gFrameStore) {
                    if (zx_ownerMatchesFrame(*kv.second, sessionId, runId, runtime)) ids.push_back(kv.first);
                }
                for (uint32_t fid : ids) {
                    removed += gFrameStore.erase(fid);
                }
            } else {
                removed = gFrameStore.size();
                gFrameStore.clear();
            }
        } else if ([lower isEqualToString:@"scoped"]) {
            if ([data count] >= 4) {
                std::string sessionId = zx_stringFromPart(data, 1, "");
                std::string runId = zx_stringFromPart(data, 2, "");
                std::string runtime = zx_stringFromPart(data, 3, "");
                std::vector<uint32_t> ids;
                for (auto const &kv : gFrameStore) {
                    if (zx_ownerMatchesFrame(*kv.second, sessionId, runId, runtime)) ids.push_back(kv.first);
                }
                for (uint32_t fid : ids) {
                    removed += gFrameStore.erase(fid);
                }
            }
        } else {
            uint32_t frameId = (uint32_t)[command intValue];
            auto it = gFrameStore.find(frameId);
            if (it != gFrameStore.end()) {
                bool allowed = true;
                if ([data count] >= 4) {
                    allowed = zx_ownerMatchesFrame(*it->second,
                                                   zx_stringFromPart(data, 1, ""),
                                                   zx_stringFromPart(data, 2, ""),
                                                   zx_stringFromPart(data, 3, ""));
                }
                if (allowed) {
                    removed = gFrameStore.erase(frameId);
                }
            }
        }
        zx_rearmFrameExpiryLocked();
    });
    return [NSString stringWithFormat:@"%lu", (unsigned long)removed];
}

