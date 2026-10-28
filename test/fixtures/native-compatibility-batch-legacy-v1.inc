// Frozen from 64a6458; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodBatch]) {
        NSArray *commands = [args count] > 0 ? [args objectAtIndex:0] : @[];
        if (![commands isKindOfClass:[NSArray class]]) return [TLinkJSNativeResponse responseWithError:@"batch(commands) requires an array" code:@-1];
        if ([commands count] > 256) return [TLinkJSNativeResponse responseWithError:@"batch(commands) accepts at most 256 commands" code:@-1];
        // RAW/mixed batches and nonstandard durations retain their exact legacy
        // grammar/intValue behavior. Select before any authorization or injection.
        bool structured=true;
        for(id item in commands) {
            if(![item isKindOfClass:[NSDictionary class]]){structured=false;break;}
            NSDictionary *cmd=item;id type=cmd[@"type"];
            if(![type isKindOfClass:[NSString class]]){structured=false;break;}
            NSString *name=[type lowercaseString];
            if([name isEqualToString:@"tap"]||[name isEqualToString:@"swipe"]) {
                id duration=cmd[@"duration"];
                if(duration&&(![duration isKindOfClass:[NSNumber class]]||
                    !TLinkautoJSIsFiniteNumber([duration doubleValue])||[duration doubleValue]<0||[duration doubleValue]>60000)) {
                    structured=false;break;
                }
            }
        }
        if(structured) {
            std::vector<TLinkNativeTouchRequest> touches;touches.reserve(commands.count);
            TLinkNativeBatchInputSize input;
            for(NSDictionary *cmd in commands) {
                TLinkNativeTouchRequest touch;size_t commandBytes=0;
                NSString *type=[cmd[@"type"] lowercaseString];
                if([type isEqualToString:@"tap"]||[type isEqualToString:@"swipe"]) {
                    const bool swipe=[type isEqualToString:@"swipe"];
                    double x=[cmd[swipe?@"x1":@"x"] doubleValue],y=[cmd[swipe?@"y1":@"y"] doubleValue];
                    double x2=swipe?[cmd[@"x2"] doubleValue]:0,y2=swipe?[cmd[@"y2"] doubleValue]:0;
                    double duration=cmd[@"duration"]?[cmd[@"duration"] doubleValue]:(swipe?300.0:50.0);
                    if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y)||!TLinkautoJSIsFiniteNumber(x2)||
                        !TLinkautoJSIsFiniteNumber(y2)||!TLinkautoJSIsFiniteNumber(duration))
                        return [TLinkJSNativeResponse responseWithError:swipe?@"batch swipe requires finite coordinates/duration":@"batch tap requires finite x/y/duration" code:@-1];
                    size_t nx=0,ny=0,nx2=0,ny2=0,nd=0;
                    touch.kind=swipe?TLinkNativeTouchKind::Swipe:TLinkNativeTouchKind::Tap;
                    touch.x1=TLinkNativeTouchJSCoordinate(x,&nx);touch.y1=TLinkNativeTouchJSCoordinate(y,&ny);
                    touch.durationMs=TLinkNativeTouchJSDuration(duration,&nd);
                    commandBytes=6+nx+ny+nd;
                    if(swipe) {
                        touch.x2=TLinkNativeTouchJSCoordinate(x2,&nx2);touch.y2=TLinkNativeTouchJSCoordinate(y2,&ny2);
                        commandBytes+=4+nx2+ny2;
                    }
                } else if([type isEqualToString:@"gesture"]) {
                    size_t pointsBytes=0;
                    if(!TLinkautoJSDecodeGesturePoints([cmd[@"points"] isKindOfClass:[NSArray class]]?cmd[@"points"]:nil,touch.points,pointsBytes))
                        return [TLinkJSNativeResponse responseWithError:@"batch gesture requires 2-512 valid points" code:@-1];
                    touch.kind=TLinkNativeTouchKind::Gesture;
                    touch.finger=cmd[@"finger"]?[cmd[@"finger"] intValue]:0;
                    int duration=cmd[@"duration"]?[cmd[@"duration"] intValue]:(cmd[@"durationMs"]?[cmd[@"durationMs"] intValue]:300);
                    touch.durationMs=duration<0?0:(duration>60000?60000:duration);
                    commandBytes=6+TLinkNativeTouchIntegerBytes(touch.finger)+TLinkNativeTouchIntegerBytes(touch.durationMs)+pointsBytes;
                } else return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"unsupported batch command type: %@",type?:@""] code:@-1];
                input.append(commandBytes);
                // Keep validating the whole input after overflow, without retaining
                // additional plans or committing any earlier command.
                if(input.fits())touches.push_back(std::move(touch));
            }
            if(!input.fits())return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
            return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouchBatch(touches,context)];
        }
        NSMutableArray<NSString *> *wireCommands = [NSMutableArray arrayWithCapacity:[commands count]];
        for (id item in commands) {
            if ([item isKindOfClass:[NSString class]]) {
                NSString *raw = (NSString *)item;
                if (TLinkautoJSStringContainsAny(raw, @[@"||", @"\r", @"\n"])) return [TLinkJSNativeResponse responseWithError:@"raw batch command contains unsupported protocol delimiter" code:@-1];
                if ([raw hasPrefix:@"62"] || [raw hasPrefix:@"63"] || [raw hasPrefix:@"64"]) [wireCommands addObject:raw];
                else return [TLinkJSNativeResponse responseWithError:@"raw batch command must start with allowed native task 62/63/64" code:@-1];
                continue;
            }
            if (![item isKindOfClass:[NSDictionary class]]) return [TLinkJSNativeResponse responseWithError:@"batch command must be an object or raw command string" code:@-1];
            NSDictionary *cmd = (NSDictionary *)item;
            NSString *type = [[cmd[@"type"] description] lowercaseString];
            if ([type isEqualToString:@"tap"]) {
                double x = [cmd[@"x"] doubleValue], y = [cmd[@"y"] doubleValue], duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 50.0;
                if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) return [TLinkJSNativeResponse responseWithError:@"batch tap requires finite x/y/duration" code:@-1];
                [wireCommands addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f", x, y, duration]];
            } else if ([type isEqualToString:@"swipe"]) {
                double x1 = [cmd[@"x1"] doubleValue], y1 = [cmd[@"y1"] doubleValue], x2 = [cmd[@"x2"] doubleValue], y2 = [cmd[@"y2"] doubleValue], duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 300.0;
                if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) || !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) return [TLinkJSNativeResponse responseWithError:@"batch swipe requires finite coordinates/duration" code:@-1];
                [wireCommands addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration]];
            } else if ([type isEqualToString:@"gesture"]) {
                NSString *encoded = TLinkautoJSEncodeGesturePoints([cmd[@"points"] isKindOfClass:[NSArray class]] ? cmd[@"points"] : nil);
                if (!encoded) return [TLinkJSNativeResponse responseWithError:@"batch gesture requires 2-512 valid points" code:@-1];
                int finger = cmd[@"finger"] ? [cmd[@"finger"] intValue] : 0;
                int duration = cmd[@"duration"] ? [cmd[@"duration"] intValue] : (cmd[@"durationMs"] ? [cmd[@"durationMs"] intValue] : 300);
                if (duration < 0) duration = 0;
                if (duration > 60000) duration = 60000;
                [wireCommands addObject:[NSString stringWithFormat:@"64%d;;%d;;%@", finger, duration, encoded]];
            } else {
                return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"unsupported batch command type: %@", type ?: @""] code:@-1];
            }
        }
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_NATIVE_BATCH, [wireCommands componentsJoinedByString:@"||"]] context:context]];
    }
    
