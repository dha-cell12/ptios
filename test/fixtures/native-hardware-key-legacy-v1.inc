// Frozen 66bb60c hardware-key compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodHardwareKey]) {
        int keyAction = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        int keyType = [args count] > 1 ? [[args objectAtIndex:1] intValue] : -1;
        if (keyType <= 0 || keyAction < 0) return [TLinkJSNativeResponse responseWithError:@"hardwareKey requires valid normalized key/action" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%d;;%d", TASK_HARDWARE_KEY, keyAction, keyType] context:context]];
    }
