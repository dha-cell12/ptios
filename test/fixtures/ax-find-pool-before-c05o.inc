static NSDictionary *TLinkAXFindInSnapshot(NSDictionary *snapshot, NSDictionary *selector)
{
    if (!TLinkAXResultSucceeded(snapshot)) return snapshot;
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    NSString *text = [selector[@"text"] isKindOfClass:[NSString class]] ? selector[@"text"] : @"";
    NSString *identifier = [selector[@"identifier"] isKindOfClass:[NSString class]] ? selector[@"identifier"] : @"";
    NSString *role = [selector[@"role"] isKindOfClass:[NSString class]] ? selector[@"role"] : @"";
    id modeValue = selector[@"match"] ?: selector[@"matchMode"];
    NSString *mode = [modeValue isKindOfClass:[NSString class]]
        ? [modeValue lowercaseString] : @"contains";
    if ([mode isEqualToString:@"equals"]) mode = @"exact";
    if (![@[@"contains", @"exact", @"prefix"] containsObject:mode]) mode = @"contains";
    id caseValue = selector[@"case_sensitive"] ?: selector[@"caseSensitive"];
    id visibleValue = selector[@"visible_only"] ?: selector[@"visibleOnly"];
    id clickableValue = selector[@"clickable_only"] ?: selector[@"clickableOnly"];
    BOOL caseSensitive = [caseValue boolValue];
    BOOL visibleOnly = visibleValue ? [visibleValue boolValue] : YES;
    BOOL clickableOnly = [clickableValue boolValue];
    NSInteger requestedIndex = TLinkAXBoundedInteger(selector[@"index"], 0, 0, 999);
    NSUInteger matchCount = 0;
    NSDictionary *selectedElement = nil;
    for (NSDictionary *element in snapshot[@"elements"]) {
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        if (visibleOnly && ![element[@"intersects_screen"] boolValue]) continue;
        if (clickableOnly && ![element[@"clickable"] boolValue]) continue;
        if (identifier.length > 0 &&
            !TLinkAXTextMatches(element[@"identifier"], identifier, mode, caseSensitive)) continue;
        if (role.length > 0 &&
            !TLinkAXTextMatches(element[@"role"], role, @"exact", caseSensitive)) continue;
        if (text.length > 0) {
            BOOL labelMatch = TLinkAXTextMatches(element[@"label"], text, mode, caseSensitive);
            BOOL valueMatch = TLinkAXTextMatches(element[@"value"], text, mode, caseSensitive);
            if (!labelMatch && !valueMatch) continue;
        }
        if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;
        ++matchCount;
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    NSDictionary *element = selectedElement;
    NSMutableDictionary *result = [snapshot mutableCopy];
    [result removeObjectForKey:@"elements"];
    result[@"schema"] = @"ui_find_v1";
    result[@"selector"] = selector ?: @{};
    result[@"found"] = @(element != nil);
    result[@"match_count"] = @(matchCount);
    result[@"element"] = element ?: @{};
    return result;
}

