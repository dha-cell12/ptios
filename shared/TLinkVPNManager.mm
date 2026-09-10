#import "TLinkVPNManager.h"

#import <NetworkExtension/NetworkExtension.h>
#import <Security/Security.h>
#import <arpa/inet.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdint.h>
#include <unistd.h>

static NSString *const kTLinkVPNDescription =
    @"TLinkauto Managed VPN (tlinkauto-managed-v1)";
static NSString *const kTLinkVPNKeychainService =
    @"com.tlinkauto.vpn.ikev2.v1";
static NSString *const kTLinkVPNKeychainAccount = @"password";
#if TLINK_VPN_TROLLSTORE_RUNTIME
static NSString *const kTLinkVPNKeychainAccessGroup =
    @"StreamCtl.com.tlinkauto.streamcontrol";
static NSString *const kTLinkVPNPrivateMarkerPath =
    @"/var/mobile/Library/TLinkauto/config/vpn-private-owned.plist";
static NSString *const kTLinkVPNPrivateNamePrefix =
    @"TLinkauto Private VPN (tlinkauto-private-v1) ";
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
        @"profile_name": kTLinkVPNDescription,
        @"backend": @"nevpnmanager_ikev2",
    };
}

static NSDictionary *TLinkVPNStatusResult(NEVPNManager *manager)
{
    return TLinkVPNResult(true, @"ok", TLinkVPNStatusFields(manager));
}

#if TLINK_VPN_TROLLSTORE_RUNTIME
static dispatch_queue_t TLinkVPNPrivateQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.tlinkauto.vpn.private-compatibility",
            DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static id TLinkVPNPrivateSendId(id target, SEL selector)
{
    if (!target || !selector || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL TLinkVPNPrivateSendBool(id target, SEL selector)
{
    if (!target || !selector || ![target respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString *TLinkVPNPrivateIdentifierString(id identifier)
{
    if ([identifier isKindOfClass:[NSString class]]) return identifier;
    if ([identifier respondsToSelector:@selector(UUIDString)]) {
        id value = TLinkVPNPrivateSendId(identifier, @selector(UUIDString));
        return [value isKindOfClass:[NSString class]] ? value : @"";
    }
    return @"";
}

static id TLinkVPNPrivateStore(NSString **failure)
{
    NSString *bundlePath =
        @"/System/Library/PreferenceBundles/VPNPreferences.bundle";
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSError *loadError = nil;
    if (!bundle || (!bundle.loaded &&
        ![bundle loadAndReturnError:&loadError])) {
        if (failure) {
            *failure = [NSString stringWithFormat:
                @"vpn_private_bundle_load_failed %@",
                loadError.localizedDescription ?: @"bundle_missing"];
        }
        return nil;
    }

    Class storeClass = NSClassFromString(@"VPNConnectionStore");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id store = TLinkVPNPrivateSendId((id)storeClass, sharedSelector);
    if (!store && failure) *failure = @"vpn_private_store_unavailable";
    return store;
}

static NSString *TLinkVPNPrivateServiceIdentifier(id service)
{
    typedef CFStringRef (*SCNetworkServiceGetServiceIDFn)(CFTypeRef service);
    static SCNetworkServiceGetServiceIDFn function = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = (SCNetworkServiceGetServiceIDFn)dlsym(
            RTLD_DEFAULT, "SCNetworkServiceGetServiceID");
        if (!function) {
            void *handle = dlopen(
                "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",
                RTLD_LAZY | RTLD_LOCAL);
            if (handle) {
                function = (SCNetworkServiceGetServiceIDFn)dlsym(
                    handle, "SCNetworkServiceGetServiceID");
            }
        }
    });
    if (!function || !service) return @"";
    CFStringRef identifier = function((__bridge CFTypeRef)service);
    return [(__bridge NSString *)identifier isKindOfClass:[NSString class]]
        ? (__bridge NSString *)identifier : @"";
}

static NSArray<NSDictionary *> *TLinkVPNPrivateConfigurationRecords(id store)
{
    id rawConfigurations = TLinkVPNPrivateSendId(
        store, NSSelectorFromString(@"configurations"));
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    if ([rawConfigurations conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id configuration in rawConfigurations) {
            id rawName = TLinkVPNPrivateSendId(configuration, @selector(name));
            id rawIdentifier = TLinkVPNPrivateSendId(
                configuration, @selector(identifier));
            NSString *name = [rawName isKindOfClass:[NSString class]]
                ? rawName : @"";
            NSString *identifier =
                TLinkVPNPrivateIdentifierString(rawIdentifier);
            if (name.length == 0 || identifier.length == 0) continue;
            [records addObject:@{
                @"name": name,
                @"identifier": identifier,
                @"raw_identifier": rawIdentifier,
            }];
        }
    }
    Class storeClass = [store class];
    id names = TLinkVPNPrivateSendId(
        (id)storeClass,
        NSSelectorFromString(@"createAllVPNByUserDefinedNamesDictionary"));
    if ([names isKindOfClass:[NSDictionary class]]) {
        [(NSDictionary *)names enumerateKeysAndObjectsUsingBlock:
            ^(id rawName, id service, BOOL *stop) {
            (void)stop;
            NSString *name = [rawName isKindOfClass:[NSString class]]
                ? rawName : @"";
            NSString *identifier =
                TLinkVPNPrivateServiceIdentifier(service);
            if (name.length == 0 || identifier.length == 0) return;
            for (NSDictionary *existing in records) {
                if ([existing[@"identifier"] isEqualToString:identifier]) {
                    return;
                }
            }
            [records addObject:@{
                @"name": name,
                @"identifier": identifier,
                @"raw_identifier": identifier,
            }];
        }];
    }
    return records;
}

static NSDictionary *TLinkVPNPrivateFindConfiguration(
    id store,
    NSString *name,
    NSString *identifier)
{
    for (NSDictionary *record in
         TLinkVPNPrivateConfigurationRecords(store)) {
        BOOL nameMatches = name.length > 0 &&
            [record[@"name"] isEqualToString:name];
        BOOL identifierMatches = identifier.length > 0 &&
            [record[@"identifier"] isEqualToString:identifier];
        if ((name.length == 0 || nameMatches) &&
            (identifier.length == 0 || identifierMatches)) {
            return record;
        }
    }
    return nil;
}

static NSDictionary *TLinkVPNPrivateLoadMarker(void)
{
    NSDictionary *marker = [NSDictionary
        dictionaryWithContentsOfFile:kTLinkVPNPrivateMarkerPath];
    if (![marker isKindOfClass:[NSDictionary class]] ||
        [marker[@"version"] integerValue] != 1 ||
        ![marker[@"backend"] isEqualToString:
            @"vpnconnectionstore_private"] ||
        ![marker[@"name"] isKindOfClass:[NSString class]] ||
        ![marker[@"name"] hasPrefix:kTLinkVPNPrivateNamePrefix] ||
        ![marker[@"identifier"] isKindOfClass:[NSString class]] ||
        [marker[@"identifier"] length] == 0) {
        return nil;
    }
    return marker;
}

static BOOL TLinkVPNPrivateWriteMarker(
    NSDictionary *record,
    NSString **failure)
{
    NSString *directory =
        [kTLinkVPNPrivateMarkerPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    if (![fm createDirectoryAtPath:directory
       withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0700}
                             error:&directoryError]) {
        if (failure) *failure = [NSString stringWithFormat:
            @"vpn_private_marker_directory_failed %@",
            directoryError.localizedDescription ?: @"unknown"];
        return NO;
    }

    NSDictionary *marker = @{
        @"version": @1,
        @"backend": @"vpnconnectionstore_private",
        @"name": record[@"name"] ?: @"",
        @"identifier": record[@"identifier"] ?: @"",
        @"selected_by_tlink": @1,
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
    };
    if (![marker writeToFile:kTLinkVPNPrivateMarkerPath atomically:YES]) {
        if (failure) *failure = @"vpn_private_marker_write_failed";
        return NO;
    }
    NSError *attributeError = nil;
    if (![fm setAttributes:@{NSFilePosixPermissions: @0600}
                    ofItemAtPath:kTLinkVPNPrivateMarkerPath
                           error:&attributeError]) {
        [fm removeItemAtPath:kTLinkVPNPrivateMarkerPath error:nil];
        if (failure) *failure = [NSString stringWithFormat:
            @"vpn_private_marker_permissions_failed %@",
            attributeError.localizedDescription ?: @"unknown"];
        return NO;
    }
    return YES;
}

static BOOL TLinkVPNPrivateSelectConfiguration(
    id store,
    NSDictionary *record)
{
    id identifier = record[@"raw_identifier"] ?: record[@"identifier"];
    SEL selector = NSSelectorFromString(@"setActiveVPNID:");
    if ([store respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(store, selector, identifier);
        if ([identifier respondsToSelector:@selector(UUIDString)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                store, selector,
                TLinkVPNPrivateIdentifierString(identifier));
        }
        return YES;
    }
    selector = NSSelectorFromString(@"setActiveVPNID:withGrade:");
    if ([store respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
            store, selector, identifier, 0);
        if ([identifier respondsToSelector:@selector(UUIDString)]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                store, selector,
                TLinkVPNPrivateIdentifierString(identifier), 0);
        }
        return YES;
    }
    return NO;
}

static id TLinkVPNPrivateCurrentConnection(id store)
{
    SEL selector = NSSelectorFromString(@"currentConnection");
    if ([store respondsToSelector:selector]) {
        return TLinkVPNPrivateSendId(store, selector);
    }
    selector = NSSelectorFromString(@"currentConnectionWithGrade:");
    if ([store respondsToSelector:selector]) {
        return ((id (*)(id, SEL, NSInteger))objc_msgSend)(
            store, selector, 0);
    }
    return nil;
}

static NSString *TLinkVPNPrivateConnectionStatus(id connection)
{
    if (!connection) return @"invalid";
    if (TLinkVPNPrivateSendBool(
            connection, NSSelectorFromString(@"connected"))) {
        return @"connected";
    }
    if (TLinkVPNPrivateSendBool(
            connection, NSSelectorFromString(@"disconnected"))) {
        return @"disconnected";
    }
    id rawText = TLinkVPNPrivateSendId(
        connection, NSSelectorFromString(@"statusText"));
    NSString *text = [rawText isKindOfClass:[NSString class]]
        ? [rawText lowercaseString] : @"";
    if ([text containsString:@"disconnecting"]) return @"disconnecting";
    if ([text containsString:@"connecting"]) return @"connecting";
    if ([text containsString:@"connected"]) return @"connected";
    if ([text containsString:@"disconnect"]) return @"disconnected";
    return text.length > 0 ? text : @"unknown";
}

static NSDictionary *TLinkVPNPrivateStatusFields(
    NSDictionary *marker,
    NSString *status)
{
    BOOL connected = [status isEqualToString:@"connected"];
    return @{
        @"profile_owned": @1,
        @"configured": @1,
        @"enabled": @1,
        @"on_demand_enabled": @0,
        @"on_demand_rule_count": @0,
        @"on_demand_mode": @"unsupported_private_backend",
        @"connection_status": status ?: @"unknown",
        @"connected": @(connected),
        @"profile_identifier": marker[@"identifier"] ?: @"",
        @"profile_name": marker[@"name"] ?: @"",
        @"backend": @"vpnconnectionstore_private",
    };
}

static NSDictionary *TLinkVPNPrivateReadStatusSync(void)
{
    NSDictionary *marker = TLinkVPNPrivateLoadMarker();
    if (!marker) {
        return TLinkVPNResult(false, @"vpn_not_configured",
            @{@"private_backend_available": @1});
    }
    NSString *failure = nil;
    id store = TLinkVPNPrivateStore(&failure);
    if (!store) return TLinkVPNResult(false,
        failure ?: @"vpn_private_store_unavailable", nil);
    NSDictionary *record = TLinkVPNPrivateFindConfiguration(
        store, marker[@"name"], marker[@"identifier"]);
    if (!record) return TLinkVPNResult(false,
        @"vpn_private_owned_profile_missing", nil);
    id connection = [marker[@"selected_by_tlink"] boolValue]
        ? TLinkVPNPrivateCurrentConnection(store) : nil;
    return TLinkVPNResult(true, @"ok",
        TLinkVPNPrivateStatusFields(
            marker, TLinkVPNPrivateConnectionStatus(connection)));
}

static BOOL TLinkVPNPrivateDeleteConfiguration(
    id store,
    NSDictionary *record)
{
    id identifier = record[@"raw_identifier"] ?: record[@"identifier"];
    SEL selector = NSSelectorFromString(@"deleteVPNWithServiceID:");
    if ([store respondsToSelector:selector]) {
        BOOL deleted = ((BOOL (*)(id, SEL, id))objc_msgSend)(
            store, selector, identifier);
        if (!deleted && [identifier respondsToSelector:@selector(UUIDString)]) {
            deleted = ((BOOL (*)(id, SEL, id))objc_msgSend)(
                store, selector,
                TLinkVPNPrivateIdentifierString(identifier));
        }
        return deleted;
    }
    selector = NSSelectorFromString(@"deleteVPNWithServiceID:withGrade:");
    if ([store respondsToSelector:selector]) {
        BOOL deleted = ((BOOL (*)(id, SEL, id, NSInteger))objc_msgSend)(
            store, selector, identifier, 0);
        if (!deleted && [identifier respondsToSelector:@selector(UUIDString)]) {
            deleted = ((BOOL (*)(id, SEL, id, NSInteger))objc_msgSend)(
                store, selector,
                TLinkVPNPrivateIdentifierString(identifier), 0);
        }
        return deleted;
    }
    return NO;
}

static NSDictionary *TLinkVPNPrivateConfigureIKEv2Sync(
    NSString *server,
    NSString *remote,
    NSString *user,
    NSString *password)
{
    NSString *failure = nil;
    id store = TLinkVPNPrivateStore(&failure);
    if (!store) return TLinkVPNResult(false,
        failure ?: @"vpn_private_store_unavailable",
        @{@"private_backend_available": @0});

    SEL createSelector = NSSelectorFromString(@"createVPNWithOptions:");
    Class storeClass = [store class];
    BOOL modernStore = [storeClass respondsToSelector:NSSelectorFromString(
        @"createAllVPNByUserDefinedNamesDictionary")];
    BOOL canList =
        [store respondsToSelector:NSSelectorFromString(@"configurations")] ||
        modernStore;
    if (![store respondsToSelector:createSelector] || !canList) {
        return TLinkVPNResult(false,
            @"vpn_private_required_selectors_missing",
            @{@"private_backend_available": @0});
    }

    NSDictionary *oldMarker = TLinkVPNPrivateLoadMarker();
    NSArray<NSDictionary *> *beforeRecords =
        TLinkVPNPrivateConfigurationRecords(store);
    NSMutableSet<NSString *> *beforeIdentifiers = [NSMutableSet set];
    for (NSDictionary *record in beforeRecords) {
        NSString *identifier = record[@"identifier"];
        if (identifier.length > 0) [beforeIdentifiers addObject:identifier];
    }
    NSString *profileName = [kTLinkVPNPrivateNamePrefix
        stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSMutableDictionary *options = [@{
        // XXTouch translates the public string "IKEv2" through its private
        // compatibility table before invoking VPNConnectionStore. The raw
        // selector expects the resulting NSNumber value (IKEv2 = 4), not the
        // source string; passing NSString can trigger an internal exception.
        @"VPNType": @4,
        @"dispName": profileName,
        @"server": server,
        // VPNConnectionStore's XXTouch-compatible schema names the EAP
        // account field "authorization".
        @"authorization": user,
        @"password": password,
        @"authType": @1,
        @"encrypLevel": @1,
        @"VPNSendAllTraffic": @1,
        @"group": @"",
        @"secret": @"",
        @"securID": @0,
    } mutableCopy];
    // On current iOS the XXTouch wrapper forwards Local/Remote identifiers
    // only when the caller supplied them. Omitting the keys is materially
    // different from forcing an empty string or copying the username/server.
    if (remote.length > 0) {
        options[@"VPNRemoteIdentifier"] = remote;
    }
    if (!modernStore) {
        // Match the compatibility defaults used by XXTouch only on older
        // VPNConnectionStore implementations.
        options[@"VPNGrade"] = @0;
        options[@"VPNLocalIdentifier"] = @"";
        options[@"VPNRemoteIdentifier"] = remote ?: @"";
        options[@"VPNRemotedentifier"] = remote ?: @"";
        options[@"eapType"] = @1;
    }
    uintptr_t created = ((uintptr_t (*)(id, SEL, id))objc_msgSend)(
        store, createSelector, options);
    if (created == 0) {
        return TLinkVPNResult(false, @"vpn_private_create_failed",
            @{@"private_backend_available": @1});
    }

    NSDictionary *newRecord = nil;
    NSString *verificationMode = @"none";
    NSUInteger verificationAttempts = 0;
    NSUInteger observedRecordCount = beforeRecords.count;
    for (NSUInteger attempt = 0; attempt < 20 && !newRecord; attempt++) {
        verificationAttempts = attempt + 1;
        NSArray<NSDictionary *> *afterRecords =
            TLinkVPNPrivateConfigurationRecords(store);
        observedRecordCount = afterRecords.count;

        for (NSDictionary *record in afterRecords) {
            if ([record[@"name"] isEqualToString:profileName]) {
                newRecord = record;
                verificationMode = @"exact_name";
                break;
            }
        }
        if (!newRecord) {
            NSMutableArray<NSDictionary *> *delta = [NSMutableArray array];
            for (NSDictionary *record in afterRecords) {
                NSString *identifier = record[@"identifier"];
                if (identifier.length > 0 &&
                    ![beforeIdentifiers containsObject:identifier]) {
                    [delta addObject:record];
                }
            }
            // The create call is serialized and uniquely named. Accept one
            // newly appearing service ID even if iOS normalizes its display
            // name; never claim ownership when the delta is ambiguous.
            if (delta.count == 1) {
                newRecord = delta.firstObject;
                verificationMode = @"single_identifier_delta";
            }
        }
        if (!newRecord && attempt + 1 < 20) {
            if ([NSThread isMainThread]) {
                // createVPNWithOptions: publishes its new SCNetworkService via
                // work delivered to the main run loop. Sleeping here prevents
                // that work from running and makes a successful create look
                // invisible forever.
                [[NSRunLoop currentRunLoop] runUntilDate:
                    [NSDate dateWithTimeIntervalSinceNow:0.1]];
            } else {
                usleep(100000);
            }
        }
    }
    if (!newRecord) {
        return TLinkVPNResult(false,
            @"vpn_private_create_verification_failed",
            @{
                @"private_backend_available": @1,
                @"verification_attempts": @(verificationAttempts),
                @"profiles_before": @(beforeRecords.count),
                @"profiles_observed": @(observedRecordCount),
                @"native_error": @"create returned success but no unique new VPN service became visible",
            });
    }
    if (!TLinkVPNPrivateSelectConfiguration(store, newRecord) ||
        !TLinkVPNPrivateCurrentConnection(store)) {
        TLinkVPNPrivateDeleteConfiguration(store, newRecord);
        return TLinkVPNResult(false,
            @"vpn_private_select_verification_failed",
            @{@"private_backend_available": @1});
    }
    if (!TLinkVPNPrivateWriteMarker(newRecord, &failure)) {
        TLinkVPNPrivateDeleteConfiguration(store, newRecord);
        return TLinkVPNResult(false,
            failure ?: @"vpn_private_marker_write_failed",
            @{@"private_backend_available": @1});
    }

    BOOL oldProfileRemoved = NO;
    if (oldMarker &&
        ![oldMarker[@"identifier"] isEqualToString:newRecord[@"identifier"]]) {
        NSDictionary *oldRecord = TLinkVPNPrivateFindConfiguration(
            store, oldMarker[@"name"], oldMarker[@"identifier"]);
        if (oldRecord &&
            [oldRecord[@"name"] hasPrefix:kTLinkVPNPrivateNamePrefix]) {
            oldProfileRemoved =
                TLinkVPNPrivateDeleteConfiguration(store, oldRecord);
        }
    }
    NSMutableDictionary *fields = [TLinkVPNPrivateStatusFields(
        @{ @"name": newRecord[@"name"],
           @"identifier": newRecord[@"identifier"] },
        @"disconnected") mutableCopy];
    fields[@"private_backend_available"] = @1;
    fields[@"verification_mode"] = verificationMode;
    fields[@"verification_attempts"] = @(verificationAttempts);
    fields[@"remote_identifier_mode"] = remote.length > 0
        ? @"explicit" : @"system_default";
    fields[@"store_schema"] = modernStore ? @"modern" : @"legacy";
    fields[@"old_owned_profile_removed"] = @(oldProfileRemoved);
    fields[@"mutating_api_exercised"] = @1;
    return TLinkVPNResult(true, @"vpn_private_profile_saved", fields);
}

static NSDictionary *TLinkVPNPrivateSetConnectedSync(
    BOOL connected,
    NSTimeInterval timeout)
{
    NSDictionary *marker = TLinkVPNPrivateLoadMarker();
    if (!marker) return TLinkVPNResult(false,
        @"vpn_not_configured", nil);
    NSString *failure = nil;
    id store = TLinkVPNPrivateStore(&failure);
    if (!store) return TLinkVPNResult(false,
        failure ?: @"vpn_private_store_unavailable", nil);
    NSDictionary *record = TLinkVPNPrivateFindConfiguration(
        store, marker[@"name"], marker[@"identifier"]);
    if (!record) return TLinkVPNResult(false,
        @"vpn_private_owned_profile_missing", nil);
    if (!TLinkVPNPrivateSelectConfiguration(store, record)) {
        return TLinkVPNResult(false,
            @"vpn_private_select_failed", nil);
    }
    id connection = TLinkVPNPrivateCurrentConnection(store);
    if (!connection) return TLinkVPNResult(false,
        @"vpn_private_connection_unavailable", nil);

    NSString *status = TLinkVPNPrivateConnectionStatus(connection);
    NSString *target = connected ? @"connected" : @"disconnected";
    if ([status isEqualToString:target]) {
        return TLinkVPNResult(true,
            connected ? @"vpn_connected" : @"vpn_disconnected",
            TLinkVPNPrivateStatusFields(marker, status));
    }

    SEL action = NSSelectorFromString(connected ? @"connect" : @"disconnect");
    if (![connection respondsToSelector:action]) {
        return TLinkVPNResult(false,
            @"vpn_private_connection_action_missing", nil);
    }
    ((void (*)(id, SEL))objc_msgSend)(connection, action);

    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] +
        MIN(MAX(timeout, 5.0), 30.0);
    do {
        usleep(100000);
        connection = TLinkVPNPrivateCurrentConnection(store);
        status = TLinkVPNPrivateConnectionStatus(connection);
        if ([status isEqualToString:target]) {
            return TLinkVPNResult(true,
                connected ? @"vpn_connected" : @"vpn_disconnected",
                TLinkVPNPrivateStatusFields(marker, status));
        }
    } while ([NSDate timeIntervalSinceReferenceDate] < deadline);

    return TLinkVPNResult(false, @"vpn_private_transition_timeout",
        TLinkVPNPrivateStatusFields(marker, status));
}

static NSDictionary *TLinkVPNPrivateRunSafely(
    NSString *operation,
    NSDictionary *(^work)(void))
{
    @try {
        NSDictionary *result = work ? work() : nil;
        return result ?: TLinkVPNResult(false,
            @"vpn_private_empty_result",
            @{@"private_backend_available": @1});
    } @catch (NSException *exception) {
        NSString *safeOperation = operation.length > 0
            ? operation : @"operation";
        NSString *code = [NSString stringWithFormat:
            @"vpn_private_%@_exception", safeOperation];
        NSLog(@"[TLinkVPN] private %@ exception %@: %@",
              safeOperation,
              exception.name ?: @"NSException",
              exception.reason ?: @"unknown");
        return TLinkVPNResult(false, code, @{
            @"private_backend_available": @1,
            @"exception_name": exception.name ?: @"NSException",
            @"native_error": exception.reason ?: @"unknown",
        });
    }
}
#endif

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
            if (!error && TLinkVPNManagerIsOwned(manager)) {
                TLinkVPNComplete(completion, TLinkVPNStatusResult(manager));
                return;
            }
#if TLINK_VPN_TROLLSTORE_RUNTIME
            dispatch_async(TLinkVPNPrivateQueue(), ^{
                NSDictionary *privateStatus =
                    TLinkVPNPrivateRunSafely(@"status", ^{
                        return TLinkVPNPrivateReadStatusSync();
                    });
                if ([privateStatus[@"ok"] boolValue]) {
                    TLinkVPNComplete(completion, privateStatus);
                    return;
                }
                if (error) {
                    TLinkVPNComplete(completion, TLinkVPNResult(false,
                        @"vpn_load_preferences_failed",
                        @{
                            @"native_error":
                                error.localizedDescription ?: @"",
                            @"private_error":
                                privateStatus[@"code"] ?: @"unknown",
                        }));
                    return;
                }
                TLinkVPNComplete(completion,
                    TLinkVPNStatusResult(manager));
            });
#else
            if (error) {
                TLinkVPNComplete(completion, TLinkVPNResult(false,
                    @"vpn_load_preferences_failed",
                    @{@"native_error": error.localizedDescription ?: @""}));
                return;
            }
            TLinkVPNComplete(completion, TLinkVPNStatusResult(manager));
#endif
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
    NSString *effectiveRemote = remote.length > 0 ? remote : server;

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

    void (^configureWithNEVPNManager)(void) = ^{
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
            protocol.remoteIdentifier = effectiveRemote;
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
    };

#if TLINK_VPN_TROLLSTORE_RUNTIME
    void (^configureWithPrivateBackend)(void) = ^{
        NSDictionary *privateResult =
            TLinkVPNPrivateRunSafely(@"configure", ^{
                return TLinkVPNPrivateConfigureIKEv2Sync(
                    server, remote, user, password);
            });
        if ([privateResult[@"private_backend_available"] boolValue]) {
            // Do not surprise the user with an iOS confirmation sheet after
            // the compatible private backend was actually available.
            TLinkVPNComplete(completion, privateResult);
            return;
        }
        configureWithNEVPNManager();
    };
    // VPNPreferences classes are UIKit/Preferences objects. Mutating them on
    // their owning main thread avoids the assertion seen when Save Profile was
    // dispatched to the background compatibility queue.
    if ([NSThread isMainThread]) {
        configureWithPrivateBackend();
    } else {
        dispatch_async(dispatch_get_main_queue(),
            configureWithPrivateBackend);
    }
#else
    configureWithNEVPNManager();
#endif
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
#if TLINK_VPN_TROLLSTORE_RUNTIME
                dispatch_async(TLinkVPNPrivateQueue(), ^{
                    NSDictionary *privateStatus =
                        TLinkVPNPrivateRunSafely(@"status", ^{
                            return TLinkVPNPrivateReadStatusSync();
                        });
                    TLinkVPNComplete(completion,
                        [privateStatus[@"ok"] boolValue]
                            ? TLinkVPNResult(false,
                                @"vpn_private_on_demand_unsupported",
                                privateStatus)
                            : TLinkVPNResult(false,
                                @"vpn_not_configured", nil));
                });
#else
                TLinkVPNComplete(completion,
                    TLinkVPNResult(false, @"vpn_not_configured", nil));
#endif
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
            if (loadError || !TLinkVPNManagerIsOwned(manager)) {
#if TLINK_VPN_TROLLSTORE_RUNTIME
                dispatch_async(TLinkVPNPrivateQueue(), ^{
                    NSDictionary *privateResult =
                        TLinkVPNPrivateRunSafely(@"connection", ^{
                            return TLinkVPNPrivateSetConnectedSync(
                                connected, boundedTimeout);
                        });
                    if (loadError &&
                        [privateResult[@"code"] isEqualToString:
                            @"vpn_not_configured"]) {
                        TLinkVPNComplete(completion, TLinkVPNResult(false,
                            @"vpn_load_preferences_failed",
                            @{
                                @"native_error":
                                    loadError.localizedDescription ?: @"",
                                @"private_error":
                                    privateResult[@"code"] ?: @"unknown",
                            }));
                        return;
                    }
                    TLinkVPNComplete(completion, privateResult);
                });
#else
                TLinkVPNComplete(completion,
                    loadError
                        ? TLinkVPNResult(false,
                            @"vpn_load_preferences_failed",
                            @{@"native_error":
                                loadError.localizedDescription ?: @""})
                        : TLinkVPNResult(false,
                            @"vpn_not_configured", nil));
#endif
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
