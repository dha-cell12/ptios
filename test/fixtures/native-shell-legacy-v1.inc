// Frozen from 965913e; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodRunShell]) {
        NSString *command = [args count] > 0 ? [args objectAtIndex:0] : @"";
        double timeoutSeconds = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        
        if ([command length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"runShell(command) requires a non-empty single-line command" code:@-1];
        }
        
        NSString *payload = command;
        if (TLinkautoJSIsFiniteNumber(timeoutSeconds) && timeoutSeconds > 0) {
            payload = [NSString stringWithFormat:@"%.3f;;%@", timeoutSeconds, command];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_RUN_SHELL, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
        
        // Base64 decode logic from original method
        NSString *encodedOutput = [parts count] > 2 ? parts[2] : @"";
        NSString *output = @"";
        if ([encodedOutput length] > 0) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encodedOutput options:0];
            if (data) output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        }
        
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"exitCode"] = @([parts[1] intValue]);
        res[@"output"] = output;
        return [TLinkJSNativeResponse responseWithValue:res];
    }
