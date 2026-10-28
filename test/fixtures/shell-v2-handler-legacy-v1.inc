// Frozen from 965913e; compatibility oracle.
    else if (taskType == TASK_RUN_SHELL_V2)
    {
        @autoreleasepool{
            NSError *jsonErr = nil;
            NSData *payloadData = [NSData dataWithBytes:eventData length:actualLength - 2];
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonErr];
            
            NSString *command = @"";
            double timeout = kShellDefaultTimeout;
            NSUInteger maxOutput = kTLinkautoJSMaxResponseBytes;
            
            if (!jsonErr && [req isKindOfClass:[NSDictionary class]]) {
                command = req[@"command"] ?: @"";
                if (req[@"timeoutSeconds"]) timeout = [req[@"timeoutSeconds"] doubleValue];
                if (req[@"maxOutputBytes"]) maxOutput = [req[@"maxOutputBytes"] unsignedIntegerValue];
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, maxOutput);
            
            NSMutableDictionary *resp = [NSMutableDictionary dictionary];
            resp[@"exitCode"] = result.exitCode == -1 ? [NSNull null] : @(result.exitCode);
            resp[@"terminationSignal"] = @(result.terminationSignal);
            resp[@"timedOut"] = @(result.timedOut);
            resp[@"cancelled"] = @(result.cancelled);
            resp[@"drainForcedClosed"] = @(result.drainForcedClosed);
            resp[@"stdout"] = result.stdoutStr;
            resp[@"stderr"] = result.stderrStr;
            resp[@"stdoutTruncated"] = @(result.stdoutTruncated);
            resp[@"stderrTruncated"] = @(result.stderrTruncated);
            
            NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            if (respData.length > kTLinkautoJSMaxResponseBytes) {
                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(true);
                resp[@"stderrTruncated"] = @(true);
                respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            }
            
            NSString *respJson = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", respJson] UTF8String], writeStreamRef);
        }
    }
