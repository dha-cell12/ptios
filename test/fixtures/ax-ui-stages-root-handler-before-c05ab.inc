static void zx_handleUITreeTask(int taskType, UInt8 *eventData, CFWriteStreamRef stream)
{
    if (taskType == TASK_UI_TREE_CAPABILITY) {
        const auto wireBudget = TLinkCurrentNativeBudget();
        auto capabilityStop = TLinkAXWireBudget::Stop(wireBudget);
        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {
            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(capabilityStop), stream);
            return;
        }
        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];
        capabilityStop = TLinkAXWireBudget::Stop(wireBudget);
        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {
            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(capabilityStop), stream);
            return;
        }
        capability[@"runtime"] = @"rootfull";
        capability[@"service"] = @"springboard_script_bridge";
        capability[@"tasks"] = @[@77, @78, @79, @80, @81];
        BOOL jsonTooLarge = false, jsonStopped = false;
        NSData *json = TLinkAXBoundedJSONDataWithStop(capability, &jsonTooLarge, &jsonStopped);
        if (jsonStopped) {
            notifyClient((UInt8 *)"-1;;ui_cancelled_or_timed_out\r\n", stream);
            return;
        }
        if (jsonTooLarge) {
            notifyClient((UInt8 *)"-1;;ui_response_too_large\r\n", stream);
            return;
        }
        if (json.length == 0) {
            notifyClient((UInt8 *)"-1;;ui_capability_json_failed\r\n", stream);
        } else {
            size_t wireBytes = 0;
            if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {
                notifyClient((UInt8 *)"-1;;ui_response_too_large\r\n", stream);
                return;
            }
            NSString *base64 = nil;
            @autoreleasepool {
                base64 = [json base64EncodedStringWithOptions:0] ?: @"";
            }
            auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
            if (admission != TLinkAXWireBudget::Admission::Ready) {
                notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);
                return;
            }
            __attribute__((objc_precise_lifetime)) NSString *response = nil;
            @autoreleasepool {
                response = [NSString stringWithFormat:@"0;;%@\r\n", base64];
            }
            @autoreleasepool {
                const char *responseBytes = response.UTF8String;
                admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
                if (admission != TLinkAXWireBudget::Admission::Ready) {
                    notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);
                    return;
                }
                notifyClient((UInt8 *)responseBytes, stream);
            }
        }
        return;
    }

    NSString *decodeError = nil;
    NSDictionary *request = zx_uiTreeRequest(eventData, taskType == TASK_UI_TREE_SNAPSHOT, &decodeError);
    if (!request) {
        notifyClient((UInt8 *)[[NSString stringWithFormat:@"-1;;%@\r\n", decodeError] UTF8String], stream);
        return;
    }
    NSDictionary *context = TLinkAXCopyFrontmostContext();
    if (!TLinkAXResultSucceeded(context)) {
        zx_uiTreeNotifyResult(context, stream);
        return;
    }
    NSString *bundleID = context[@"bundle_id"];
    pid_t pid = [context[@"pid"] intValue];
    NSDictionary *result = nil;
    if (taskType == TASK_UI_TREE_SNAPSHOT) {
        result = TLinkAXCopySnapshot(pid, bundleID, request);
    } else if (taskType == TASK_UI_TREE_FIND || taskType == TASK_UI_TREE_TAP) {
        result = TLinkAXFindElement(pid, bundleID, request);
    } else if (taskType == TASK_UI_TREE_AT) {
        id x = request[@"x"], y = request[@"y"];
        if (![x respondsToSelector:@selector(doubleValue)] || ![y respondsToSelector:@selector(doubleValue)]) {
            notifyClient((UInt8 *)"-1;;ui_hit_test_coordinates_required\r\n", stream);
            return;
        }
        result = TLinkAXElementAtPoint(pid, bundleID, CGPointMake([x doubleValue], [y doubleValue]));
    }
    if (!TLinkAXResultSucceeded(result)) {
        zx_uiTreeNotifyResult(result, stream);
        return;
    }
    if (taskType == TASK_UI_TREE_TAP && !TLinkAXResultCompleteForAction(result)) {
        notifyClient((UInt8 *)"-1;;ui_snapshot_incomplete\r\n", stream);
        return;
    }
    if (zx_uiTreeContextChanged(context)) {
        notifyClient((UInt8 *)"-1;;ui_context_changed\r\n", stream);
        return;
    }
    NSMutableDictionary *finalResult = [result mutableCopy];
    finalResult[@"runtime"] = @"rootfull";
    finalResult[@"context_changed"] = @(false);
    if (taskType == TASK_UI_TREE_TAP) {
        NSDictionary *element = [finalResult[@"element"] isKindOfClass:[NSDictionary class]]
            ? finalResult[@"element"] : @{};
        if (![finalResult[@"found"] boolValue] || element.count == 0) {
            notifyClient((UInt8 *)"-1;;ui_element_not_found\r\n", stream);
            return;
        }
        if (![element[@"enabled"] boolValue] || ![element[@"clickable"] boolValue]) {
            notifyClient((UInt8 *)"-1;;ui_element_not_clickable\r\n", stream);
            return;
        }
        if (![element[@"activation_point_valid"] boolValue]) {
            notifyClient((UInt8 *)"-1;;ui_activation_point_invalid\r\n", stream);
            return;
        }
        NSDictionary *point = element[@"activation_point"];
        CGFloat pointScale = [UIScreen mainScreen].scale > 0.0 ? [UIScreen mainScreen].scale : 1.0;
        NSString *tap = [NSString stringWithFormat:@"%.3f;;%.3f;;50;;0",
                         [point[@"x"] doubleValue] * pointScale,
                         [point[@"y"] doubleValue] * pointScale];
        NSError *tapError = nil;
        if (!zx_handleNativeTap((UInt8 *)[tap UTF8String], &tapError)) {
            notifyClient((UInt8 *)"-1;;ui_tap_dispatch_failed\r\n", stream);
            return;
        }
        finalResult[@"schema"] = @"ui_tap_v1";
        finalResult[@"tapped"] = @(true);
    }
    zx_uiTreeNotifyResult(finalResult, stream);
}

