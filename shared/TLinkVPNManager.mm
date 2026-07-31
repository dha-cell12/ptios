#import "TLinkVPNManager.h"

#import <NetworkExtension/NetworkExtension.h>
#import <Security/Security.h>
#import <arpa/inet.h>

static NSString *const kTLinkVPNDescription =
    @"TLinkauto Managed VPN (tlinkauto-managed-v1)";
static NSString *const kTLinkVPNKeychainService =
    @"com.tlinkauto.vpn.ikev2.v1";
static NSString *const kTLinkVPNKeychainAccount = @"password";
#if TLINK_VPN_TROLLSTORE_RUNTIME
static NSString *const kTLinkVPNKeychainAccessGroup =
    @"StreamCtl.com.tlinkauto.streamcontrol";
#else
static NSString *const kTLinkVPNKeychainAccessGroup =
    @"com.tlinkauto.tlinkauto";
#endif

NSString *TLinkVPNOwnedDescription(void)
{
    return kTLinkVPNDescription;
}

static NSDictionary *TLinkVPNResult(
    BOOL ok,
    NSString *code,
    NSDictionary *extra)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
        @"ok": @(ok),
        @"code": code ?: (ok ? @"ok" : @"unknown_error"),
    }];
    if (extra) [result addEntriesFromDictionary:extra];
    return result;
}

static NSString *TLinkVPNStatusName(NEVPNStatus status)
{
    switch (status) {
        case NEVPNStatusInvalid: return @"invalid";
        case NEVPNStatusDisconnected: return @"disconnected";
        case NEVPNStatusConnecting: return @"connecting";
        case NEVPNStatusConnected: return @"connected";
        case NEVPNStatusReasserting: return @"reasserting";
        case NEVPNStatusDisconnecting: return @"disconnecting";
        default: return @"unknown";
    }
}

static BOOL TLinkVPNManagerIsOwned(NEVPNManager *manager)
{
    return manager.protocolConfiguration != nil &&
           [manager.localizedDescription isEqualToString:kTLinkVPNDescription];
}

static BOOL TLinkVPNServerIsLoopback(NSString *serverAddress)
{
    NSString *candidate = [[serverAddress
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (candidate.length == 0) return false;
    if ([candidate isEqualToString:@"localhost"]) return true;
    if ([candidate hasPrefix:@"["] && [candidate hasSuffix:@"]"] &&
        candidate.length > 2) {
        candidate = [candidate substringWithRange:
            NSMakeRange(1, candidate.length - 2)];
    }

    struct in_addr ipv4;
    if (inet_pton(AF_INET, candidate.UTF8String, &ipv4) == 1) {
        return (ntohl(ipv4.s_addr) & 0xff000000U) == 0x7f000000U;
    }
    struct in6_addr ipv6;
    if (inet_pton(AF_INET6, candidate.UTF8String, &ipv6) == 1) {
        return IN6_IS_ADDR_LOOPBACK(&ipv6);
    }
    return false;
}

static NSDictionary *TLinkVPNStatusFields(NEVPNManager *manager)
{
    BOOL owned = TLinkVPNManagerIsOwned(manager);
    BOOL onDemandEnabled = owned && manager.onDemandEnabled;
    NEVPNStatus connectionStatus = manager.connection
        ? manager.connection.status
        : NEVPNStatusInvalid;
    return @{
        @"profile_owned": @(owned),
        @"configured": @(owned && manager.protocolConfiguration != nil),
        @"enabled": @(owned && manager.enabled),
        @"on_demand_enabled": @(onDemandEnabled),
        @"on_demand_rule_count": @(owned ? manager.onDemandRules.count : 0),
        @"on_demand_mode": onDemandEnabled
            ? @"connect_all_networks"
            : @"disabled",
        @"connection_status": TLinkVPNStatusName(connectionStatus),
        @"connected": @(owned && connectionStatus == NEVPNStatusConnected),
        @"profile_identifier": @"tlinkauto-managed-v1",
    };
}

static NSDictionary *TLinkVPNStatusResult(NEVPNManager *manager)
{
    return TLinkVPNResult(true, @"ok", TLinkVPNStatusFields(manager));
}

static NSData *TLinkVPNStorePassword(
    NSString *password,
    NSError **error)
{
    NSData *passwordData =
        [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTLinkVPNKeychainService,
        (__bridge id)kSecAttrAccount: kTLinkVPNKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kTLinkVPNKeychainAccessGroup,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary *add =
        [NSMutableDictionary dictionaryWithDictionary:query];
    add[(__bridge id)kSecValueData] = passwordData;
    add[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    add[(__bridge id)kSecReturnPersistentRef] =
        (__bridge id)kCFBooleanTrue;

    CFTypeRef result = NULL;
    OSStatus status = SecItemAdd(
        (__bridge CFDictionaryRef)add,
        &result);
    if (status != errSecSuccess || !result) {
        if (result) CFRelease(result);
        OSStatus effectiveStatus = status == errSecSuccess
            ? errSecInternalComponent
            : status;
        CFStringRef statusMessage =
            SecCopyErrorMessageString(effectiveStatus, NULL);
        NSString *nativeError = CFBridgingRelease(statusMessage) ?: @"";
        NSLog(@"[TLinkVPN] password persistent reference save failed OSStatus=%d",
              (int)effectiveStatus);
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:effectiveStatus
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"vpn_keychain_password_save_failed",
                @"native_error": nativeError,
                @"os_status": @(effectiveStatus),
            }];
        }
        return nil;
    }
    return CFBridgingRelease(result);
}

static void TLinkVPNComplete(
    TLinkVPNResultCompletion completion,
    NSDictionary *result)
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result ?: TLinkVPNResult(false, @"unknown_error", nil));
    });
}

void TLinkVPNReadManagerStatus(TLinkVPNResultCompletion completion)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NEVPNManager *manager = [NEVPNManager sharedManager];
        [manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            if (error) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_load_preferences_failed",
                    @{@"native_error": error.localizedDescription ?: @""}));
                return;
            }
            TLinkVPNComplete(completion, TLinkVPNStatusResult(manager));
        }];
    });
}

void TLinkVPNConfigureIKEv2(
    NSString *serverAddress,
    NSString *remoteIdentifier,
    NSString *username,
    NSString *password,
    TLinkVPNResultCompletion completion)
{
    NSString *server = [serverAddress
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *remote = [remoteIdentifier
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *user = [username
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (server.length == 0 || user.length == 0 || password.length == 0) {
        TLinkVPNComplete(completion,
            TLinkVPNResult(false, @"vpn_configuration_incomplete", nil));
        return;
    }
    if (TLinkVPNServerIsLoopback(server)) {
        TLinkVPNComplete(completion,
            TLinkVPNResult(false, @"vpn_server_loopback_not_allowed", nil));
        return;
    }
    if (remote.length == 0) remote = server;

    NSError *keychainError = nil;
    NSData *passwordReference =
        TLinkVPNStorePassword(password, &keychainError);
    if (!passwordReference) {
        TLinkVPNComplete(completion, TLinkVPNResult(false,
            @"vpn_keychain_password_save_failed",
            @{
                @"os_status": keychainError.userInfo[@"os_status"]
                    ?: @(keychainError.code),
                @"native_error": keychainError.userInfo[@"native_error"] ?: @"",
            }));
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NEVPNManager *manager = [NEVPNManager sharedManager];
        [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
            if (loadError) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_load_preferences_failed",
                    @{@"native_error": loadError.localizedDescription ?: @""}));
                return;
            }
            if (manager.protocolConfiguration != nil &&
                !TLinkVPNManagerIsOwned(manager)) {
                TLinkVPNComplete(completion,
                    TLinkVPNResult(false, @"vpn_foreign_profile_present", nil));
                return;
            }

            NEVPNProtocolIKEv2 *protocol = [[NEVPNProtocolIKEv2 alloc] init];
            protocol.serverAddress = server;
            protocol.remoteIdentifier = remote;
            protocol.username = user;
            protocol.passwordReference = passwordReference;
            protocol.authenticationMethod = NEVPNIKEAuthenticationMethodNone;
            protocol.useExtendedAuthentication = true;
            protocol.disconnectOnSleep = false;

            protocol.IKESecurityAssociationParameters.encryptionAlgorithm =
                NEVPNIKEv2EncryptionAlgorithmAES256;
            protocol.IKESecurityAssociationParameters.integrityAlgorithm =
                NEVPNIKEv2IntegrityAlgorithmSHA256;
            protocol.IKESecurityAssociationParameters.diffieHellmanGroup =
                NEVPNIKEv2DiffieHellmanGroup14;
            protocol.childSecurityAssociationParameters.encryptionAlgorithm =
                NEVPNIKEv2EncryptionAlgorithmAES256;
            protocol.childSecurityAssociationParameters.integrityAlgorithm =
                NEVPNIKEv2IntegrityAlgorithmSHA256;
            protocol.childSecurityAssociationParameters.diffieHellmanGroup =
                NEVPNIKEv2DiffieHellmanGroup14;

            manager.localizedDescription = kTLinkVPNDescription;
            manager.protocolConfiguration = protocol;
            manager.onDemandEnabled = false;
            manager.onDemandRules = @[];
            manager.enabled = true;

            [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                if (saveError) {
                    TLinkVPNComplete(completion, TLinkVPNResult(false,
                        @"vpn_save_preferences_failed",
                        @{@"native_error": saveError.localizedDescription ?: @""}));
                    return;
                }
                [manager loadFromPreferencesWithCompletionHandler:^(NSError *reloadError) {
                    if (reloadError) {
                        TLinkVPNComplete(completion, TLinkVPNResult(false,
                            @"vpn_reload_preferences_failed",
                            @{@"native_error": reloadError.localizedDescription ?: @""}));
                        return;
                    }
                    TLinkVPNComplete(completion,
                        TLinkVPNResult(true, @"vpn_profile_saved",
                            TLinkVPNStatusFields(manager)));
                }];
            }];
        }];
    });
}

void TLinkVPNSetOnDemandEnabled(
    BOOL enabled,
    TLinkVPNResultCompletion completion)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NEVPNManager *manager = [NEVPNManager sharedManager];
        [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
            if (loadError) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_load_preferences_failed",
                    @{@"native_error": loadError.localizedDescription ?: @""}));
                return;
            }
            if (!TLinkVPNManagerIsOwned(manager)) {
                TLinkVPNComplete(completion,
                    TLinkVPNResult(false, @"vpn_not_configured", nil));
                return;
            }

            if (enabled) {
                NEOnDemandRuleConnect *connectRule =
                    [[NEOnDemandRuleConnect alloc] init];
                manager.onDemandRules = @[connectRule];
                manager.onDemandEnabled = true;
                manager.enabled = true;
            } else {
                manager.onDemandEnabled = false;
                manager.onDemandRules = @[];
            }

            [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                if (saveError) {
                    TLinkVPNComplete(completion, TLinkVPNResult(false,
                        @"vpn_on_demand_save_failed",
                        @{@"native_error": saveError.localizedDescription ?: @""}));
                    return;
                }
                [manager loadFromPreferencesWithCompletionHandler:^(NSError *reloadError) {
                    if (reloadError) {
                        TLinkVPNComplete(completion, TLinkVPNResult(false,
                            @"vpn_reload_preferences_failed",
                            @{@"native_error": reloadError.localizedDescription ?: @""}));
                        return;
                    }
                    BOOL applied = manager.onDemandEnabled == enabled &&
                        (!enabled || manager.onDemandRules.count > 0);
                    TLinkVPNComplete(completion, TLinkVPNResult(
                        applied,
                        applied
                            ? (enabled
                                ? @"vpn_on_demand_enabled"
                                : @"vpn_on_demand_disabled")
                            : @"vpn_on_demand_verification_failed",
                        TLinkVPNStatusFields(manager)));
                }];
            }];
        }];
    });
}

void TLinkVPNSetConnected(
    BOOL connected,
    NSTimeInterval timeout,
    TLinkVPNResultCompletion completion)
{
    NSTimeInterval boundedTimeout = MIN(MAX(timeout, 5.0), 30.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        NEVPNManager *manager = [NEVPNManager sharedManager];
        [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
            if (loadError) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_load_preferences_failed",
                    @{@"native_error": loadError.localizedDescription ?: @""}));
                return;
            }
            if (!TLinkVPNManagerIsOwned(manager)) {
                TLinkVPNComplete(completion,
                    TLinkVPNResult(false, @"vpn_not_configured", nil));
                return;
            }
            if (!manager.enabled) {
                TLinkVPNComplete(completion,
                    TLinkVPNResult(false, @"vpn_profile_disabled", nil));
                return;
            }
            if (connected && TLinkVPNServerIsLoopback(
                    manager.protocolConfiguration.serverAddress)) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_server_loopback_not_allowed",
                    TLinkVPNStatusFields(manager)));
                return;
            }
            if (!connected && manager.onDemandEnabled) {
                TLinkVPNSetOnDemandEnabled(false,
                    ^(NSDictionary *onDemandResult) {
                    if (![onDemandResult[@"ok"] boolValue]) {
                        TLinkVPNComplete(completion, TLinkVPNResult(false,
                            @"vpn_disconnect_disable_on_demand_failed",
                            @{
                                @"native_error":
                                    onDemandResult[@"native_error"] ?: @"",
                                @"on_demand_error":
                                    onDemandResult[@"code"] ?: @"unknown",
                            }));
                        return;
                    }
                    TLinkVPNSetConnected(false, timeout, completion);
                });
                return;
            }

            NEVPNStatus target = connected
                ? NEVPNStatusConnected
                : NEVPNStatusDisconnected;
            if (manager.connection.status == target) {
                TLinkVPNComplete(completion,
                    TLinkVPNResult(true,
                        connected ? @"vpn_connected" : @"vpn_disconnected",
                        TLinkVPNStatusFields(manager)));
                return;
            }

            __block id observer = nil;
            __block BOOL completed = false;
            void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
                if (completed) return;
                completed = true;
                if (observer) {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    observer = nil;
                }
                TLinkVPNComplete(completion, result);
            };

            observer = [[NSNotificationCenter defaultCenter]
                addObserverForName:NEVPNStatusDidChangeNotification
                            object:manager.connection
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *notification) {
                NEVPNStatus status = manager.connection.status;
                if (status == target) {
                    finish(TLinkVPNResult(true,
                        connected ? @"vpn_connected" : @"vpn_disconnected",
                        TLinkVPNStatusFields(manager)));
                } else if (connected && status == NEVPNStatusInvalid) {
                    finish(TLinkVPNResult(false,
                        @"vpn_connection_became_invalid",
                        TLinkVPNStatusFields(manager)));
                } else if (connected && status == NEVPNStatusDisconnected) {
                    finish(TLinkVPNResult(false,
                        @"vpn_connection_failed",
                        TLinkVPNStatusFields(manager)));
                }
            }];

            if (connected) {
                NSError *startError = nil;
                BOOL started =
                    [manager.connection startVPNTunnelAndReturnError:&startError];
                if (!started || startError) {
                    finish(TLinkVPNResult(false,
                        @"vpn_start_failed",
                        @{@"native_error":
                              startError.localizedDescription ?: @""}));
                    return;
                }
            } else {
                [manager.connection stopVPNTunnel];
            }

            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(boundedTimeout * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                finish(TLinkVPNResult(false,
                    @"vpn_transition_timeout",
                    TLinkVPNStatusFields(manager)));
            });
        }];
    });
}
