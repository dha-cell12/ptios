static BOOL TLinkAXTextMatches(NSString *candidate,
                               NSString *expected,
                               NSString *mode,
                               BOOL caseSensitive)
{
    if (expected.length == 0) return YES;
    NSString *left = candidate ?: @"";
    NSString *right = expected;
    if (!caseSensitive) {
        left = [left lowercaseString];
        right = [right lowercaseString];
    }
    if ([mode isEqualToString:@"exact"]) return [left isEqualToString:right];
    if ([mode isEqualToString:@"prefix"]) return [left hasPrefix:right];
    return [left rangeOfString:right].location != NSNotFound;
}

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
    TLinkAXSelectorPlan::Text identifierPlan(identifier, mode, caseSensitive);
    TLinkAXSelectorPlan::Text rolePlan(role, @"exact", caseSensitive);
    TLinkAXSelectorPlan::Text textPlan(text, mode, caseSensitive);
    NSUInteger matchCount = 0;
    NSDictionary *selectedElement = nil;
    for (NSDictionary *element in snapshot[@"elements"]) {
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        @autoreleasepool {
            if (visibleOnly && ![element[@"intersects_screen"] boolValue]) continue;
            if (clickableOnly && ![element[@"clickable"] boolValue]) continue;
            if (identifier.length > 0 &&
                !identifierPlan.accepts(element[@"identifier"], TLinkAXTextMatches)) continue;
            if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
            if (role.length > 0 &&
                !rolePlan.accepts(element[@"role"], TLinkAXTextMatches)) continue;
            if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
            if (text.length > 0) {
                BOOL labelMatch = textPlan.accepts(element[@"label"], TLinkAXTextMatches);
                if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
                BOOL valueMatch = textPlan.accepts(element[@"value"], TLinkAXTextMatches);
                if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
                if (!labelMatch && !valueMatch) continue;
            }
            if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
            if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;
            ++matchCount;
        }
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
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    return result;
}

NSDictionary *TLinkAXFindElement(pid_t pid, NSString *bundleID, NSDictionary *selector)
{
    if (![selector isKindOfClass:[NSDictionary class]]) {
        return TLinkAXError(@"ui_selector_invalid", @{@"pid": @(pid)});
    }
    NSString *text = [selector[@"text"] isKindOfClass:[NSString class]] ? selector[@"text"] : @"";
    NSString *identifier = [selector[@"identifier"] isKindOfClass:[NSString class]] ? selector[@"identifier"] : @"";
    NSString *role = [selector[@"role"] isKindOfClass:[NSString class]] ? selector[@"role"] : @"";
    if (text.length == 0 && identifier.length == 0 && role.length == 0) {
        return TLinkAXError(@"ui_selector_requires_text_identifier_or_role", @{@"pid": @(pid)});
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    id modeValue = selector[@"match"] ?: selector[@"matchMode"];
    NSString *mode = [modeValue isKindOfClass:[NSString class]] ? modeValue : @"";
    if (!TLinkAXSelectorPlan::Admit(text) || !TLinkAXSelectorPlan::Admit(identifier) ||
        !TLinkAXSelectorPlan::Admit(role) || !TLinkAXSelectorPlan::Admit(mode))
        return TLinkAXError(@"ui_response_too_large", @{@"pid": @(pid), @"partial": @YES});
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"max_elements"] = selector[@"max_elements"] ?: selector[@"maxElements"] ?: @250;
    options[@"max_scanned_elements"] = selector[@"max_scanned_elements"] ?: selector[@"maxScannedElements"] ?: @(kTLinkAXDefaultMaxScannedElements);
    options[@"timeout_ms"] = selector[@"timeout_ms"] ?: selector[@"timeoutMs"] ?: @1500;
    options[@"allow_locked"] = selector[@"allow_locked"] ?: selector[@"allowLocked"] ?: @NO;
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        @autoreleasepool {
            NSDictionary *snapshot = TLinkAXCopySnapshotUnlocked(pid, bundleID ?: @"", options);
            result = TLinkAXFindInSnapshot(snapshot, selector);
        }
    });
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    return result ?: TLinkAXError(@"ui_find_failed", @{@"pid": @(pid)});
}

