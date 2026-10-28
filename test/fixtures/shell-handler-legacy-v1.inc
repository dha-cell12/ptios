// Frozen from 965913e; compatibility oracle.
    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
            NSString *rawPayload = [NSString stringWithUTF8String:(const char *)eventData] ?: @"";
            double timeout = kShellDefaultTimeout;
            NSString *command = rawPayload;
            NSRange sepRange = [rawPayload rangeOfString:@";;"];
            if (sepRange.location != NSNotFound) {
                NSString *maybeTimeout = [rawPayload substringToIndex:sepRange.location];
                NSScanner *scanner = [NSScanner scannerWithString:maybeTimeout];
                double parsed = 0;
                if ([scanner scanDouble:&parsed] && [scanner isAtEnd] && parsed > 0) {
                    timeout = parsed;
                    command = [rawPayload substringFromIndex:sepRange.location + 2];
                }
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, SIZE_MAX);
            
            NSString *combined = result.stderrStr.length > 0 ? [result.stdoutStr stringByAppendingString:result.stderrStr] : result.stdoutStr;
            NSString *safeOutput = [[combined stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            if (result.stdoutTruncated || result.stderrTruncated) {
                safeOutput = [safeOutput stringByAppendingFormat:@"\\n[output truncated: exceeded %lu bytes]", (unsigned long)kShellMaxCapturedOutputBytes];
            }
            
            if (result.timedOut) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command timed out after %.0fs: %@\r\n", timeout, safeOutput] UTF8String], writeStreamRef);
            } else if (result.cancelled) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command cancelled: %@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else if (result.exitCode == 0) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed (%d): %@\r\n", result.exitCode, safeOutput] UTF8String], writeStreamRef);
            }
        }
    }
