// Frozen from 2b06a1f; compatibility oracle.
NSString* vpnTaskFromRawData(UInt8 *eventData, NSError **error)
{
    // P1 exposes read-only, base64-JSON diagnostics. Query/control remain at
    // the frozen P0 baseline until an entitled broker is proven on device.
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    if (action == 2) {
        NSString *raw = [NSString stringWithFormat:@"%s", eventData ?: (UInt8*)""];
        NSArray *parts = [raw componentsSeparatedByString:@";;"];
        if ([parts count] != 1) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"-1;;vpn_diagnostics_takes_no_arguments\r\n"
                }];
            }
            return nil;
        }
        NSString *brokerError = nil;
        NSString *base64 = zx_vpnBrokerRequest(@"diagnostics", &brokerError);
        if (base64.length > 0) return base64;

        NSError *diagnosticsError = nil;
        base64 = TLinkVPNDiagnosticsBase64(
            @"rootfull",
            @"broker_unavailable",
            @"app_broker_6014",
            @"app_broker_6014",
            @"nevpnmanager_ikev2",
            @"tlinkauto_vpnd_6014",
            nil,
            &diagnosticsError);
        if (!base64) {
            if (error) {
                NSString *message = diagnosticsError.localizedDescription
                    ?: @"vpn_diagnostics_encode_failed";
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"-1;;%@\r\n", message]
                }];
            }
            return nil;
        }
        return base64;
    }

    if (action != 0 && action != 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{
                NSLocalizedDescriptionKey:
                    @"-1;;connectivity_action_must_be_0_query_1_set_or_2_diagnostics\r\n"
            }];
        }
        return nil;
    }

    NSString *brokerError = nil;
    NSString *command = action == 0
        ? @"query"
        : (value ? @"connect" : @"disconnect");
    NSString *state = zx_vpnBrokerRequest(command, &brokerError);
    if (state.length > 0) return state;

    if (error) {
        NSString *message = brokerError ?: @"vpn_broker_unavailable";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{
            NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"-1;;%@\r\n", message]
        }];
    }
    return nil;
}
