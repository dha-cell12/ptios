static NSData *TLinkHandleUITreeTask(int taskType, NSString *body)
{
    if (taskType == 77) {
        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];
        CFAbsoluteTime resolveStarted = CFAbsoluteTimeGetCurrent();
        NSDictionary *foreground = TLinkUITreeFrontmostContext();
        NSInteger resolveDurationMs = (NSInteger)llround(
            (CFAbsoluteTimeGetCurrent() - resolveStarted) * 1000.0);
        capability[@"runtime"] = @"trollstore";
        capability[@"service"] = @"streamd";
        capability[@"implementation_version"] = @12;
        capability[@"tasks"] = @[@77, @78, @79, @80, @81];
        capability[@"foreground_context"] = @{
            @"ok": @([foreground[@"ok"] boolValue]),
            @"bundle_id": foreground[@"bundle_id"] ?: @"",
            @"pid": foreground[@"pid"] ?: @0,
            @"source": foreground[@"source"] ?: @"",
            @"error": foreground[@"error"] ?: @"",
            @"diagnostic": foreground[@"diagnostic"] ?: @"",
            @"ax_probe_error": foreground[@"ax_probe_error"] ?: @"",
            @"fallback_error": foreground[@"fallback_error"] ?: @"",
            @"generation": foreground[@"generation"] ?: @(sTLinkUITreeContextGeneration),
            @"verification_count": foreground[@"verification_count"] ?: @0,
            @"direct_retry_count": foreground[@"direct_retry_count"] ?: @0,
            @"state": foreground[@"state"] ?: @"unresolved",
            @"resolve_duration_ms": @(resolveDurationMs),
            @"legacy_foreground_hot_path_disabled": @(sTLinkUITreeLegacyForegroundUnavailable),
            @"direct_foreground_state": sTLinkAXSpringBoardState ?: @"unprobed",
            @"direct_foreground_error": sTLinkAXSpringBoardError ?: @"",
            @"direct_foreground_diagnostic": sTLinkAXSpringBoardDiagnostic ?: @"",
            @"direct_foreground_resolve_duration_ms": @(sTLinkAXSpringBoardLastResolveMs),
            @"direct_foreground_focused_pid": @(sTLinkAXSpringBoardLastFocusedPid),
            @"direct_foreground_top_event_pid": @(sTLinkAXSpringBoardLastTopEventPid),
        };
        const auto wireBudget = TLinkCurrentNativeBudget();
        BOOL jsonTooLarge = false, jsonStopped = false;
        NSData *json = TLinkAXBoundedJSONDataWithStop(capability, &jsonTooLarge, &jsonStopped);
        if (jsonStopped) {
            return TLinkError(@"ui_cancelled_or_timed_out");
        }
        if (jsonTooLarge) {
            return TLinkError(@"ui_response_too_large");
        }
        if (json.length == 0) return TLinkError(@"ui_capability_json_failed");
        size_t wireBytes = 0;
        if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {
            return TLinkError(@"ui_response_too_large");
        }
        NSString *base64 = nil;
        @autoreleasepool {
            base64 = [json base64EncodedStringWithOptions:0] ?: @"";
        }
        auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
        if (admission != TLinkAXWireBudget::Admission::Ready) {
            return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped
                ? @"ui_cancelled_or_timed_out" : @"ui_response_too_large");
        }
        NSData *response = nil;
        @autoreleasepool {
            response = TLinkSuccess(base64);
        }
        admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
        if (admission != TLinkAXWireBudget::Admission::Ready) {
            return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped
                ? @"ui_cancelled_or_timed_out" : @"ui_response_too_large");
        }
        return response;
    }

    NSString *decodeError = nil;
    NSDictionary *request = TLinkUITreeDecodeBody(body, taskType == 78, &decodeError);
    if (!request) return TLinkError(decodeError);
    NSDictionary *context = TLinkUITreeFrontmostContext();
    if (![context[@"ok"] boolValue]) return TLinkError(context[@"error"] ?: @"ui_frontmost_unavailable");
    NSString *bundleId = context[@"bundle_id"];
    pid_t pid = [context[@"pid"] intValue];
    NSDictionary *result = nil;

    for (int attempt = 0; attempt < 2; attempt++) {
        if (taskType == 78) {
            result = TLinkAXCopySnapshot(pid, bundleId, request);
        } else if (taskType == 79 || taskType == 81) {
            result = TLinkAXFindElement(pid, bundleId, request);
        } else if (taskType == 80) {
            id xValue = request[@"x"];
            id yValue = request[@"y"];
            if (![xValue respondsToSelector:@selector(doubleValue)] ||
                ![yValue respondsToSelector:@selector(doubleValue)]) {
                return TLinkError(@"ui_hit_test_coordinates_required");
            }
            result = TLinkAXElementAtPoint(pid, bundleId,
                                          CGPointMake([xValue doubleValue], [yValue doubleValue]));
        } else {
            return TLinkError(@"ui_task_unsupported");
        }

        NSString *resultError = [result[@"error"] isKindOfClass:[NSString class]]
            ? result[@"error"] : @"";
        if (TLinkAXResultSucceeded(result) || attempt > 0 ||
            ![resultError isEqualToString:@"ui_element_query_failed"]) break;

        // The app may have changed between the context probe and the real
        // query. Drop the short cache, resolve once more, then retry safely.
        TLinkUITreeInvalidateCachedContext();
        NSDictionary *retryContext = TLinkUITreeFrontmostContext();
        if (![retryContext[@"ok"] boolValue]) break;
        context = retryContext;
        bundleId = context[@"bundle_id"];
        pid = [context[@"pid"] intValue];
    }

    if (!TLinkAXResultSucceeded(result)) return TLinkUITreeJSONResponse(result);
    if (taskType == 81 && !TLinkAXResultCompleteForAction(result)) {
        return TLinkError(@"ui_snapshot_incomplete");
    }
    BOOL changed = TLinkUITreeContextChanged(context);
    NSMutableDictionary *finalResult = [result mutableCopy];
    finalResult[@"runtime"] = @"trollstore";
    finalResult[@"context_changed"] = @(changed);
    if (changed) {
        finalResult[@"ok"] = @NO;
        finalResult[@"error"] = @"ui_context_changed";
        return TLinkUITreeJSONResponse(finalResult);
    }

    if (taskType == 81) {
        NSDictionary *element = [finalResult[@"element"] isKindOfClass:[NSDictionary class]]
            ? finalResult[@"element"] : @{};
        if (![finalResult[@"found"] boolValue] || element.count == 0) {
            return TLinkError(@"ui_element_not_found");
        }
        if (![element[@"enabled"] boolValue] || ![element[@"clickable"] boolValue]) {
            return TLinkError(@"ui_element_not_clickable");
        }
        if (![element[@"activation_point_valid"] boolValue]) {
            return TLinkError(@"ui_activation_point_invalid");
        }
        NSDictionary *point = [element[@"activation_point"] isKindOfClass:[NSDictionary class]]
            ? element[@"activation_point"] : @{};
        CGFloat pointScale = [UIScreen mainScreen].scale > 0.0 ? [UIScreen mainScreen].scale : 1.0;
        NSString *tapBody = [NSString stringWithFormat:@"%.3f;;%.3f;;50;;0",
                             [point[@"x"] doubleValue] * pointScale,
                             [point[@"y"] doubleValue] * pointScale];
        NSString *tapError = nil;
        if (!TLinkHandleNativeTap(tapBody, &tapError)) {
            return TLinkError(tapError ?: @"ui_tap_dispatch_failed");
        }
        finalResult[@"schema"] = @"ui_tap_v1";
        finalResult[@"tapped"] = @YES;
    }
    return TLinkUITreeJSONResponse(finalResult);
}

