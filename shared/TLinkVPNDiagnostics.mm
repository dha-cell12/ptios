#import "TLinkVPNDiagnostics.h"

#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdint.h>
#import <objc/message.h>

typedef struct __SecTask *SecTaskRef;

extern "C" {
SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
CFTypeRef SecTaskCopyValueForEntitlement(
    SecTaskRef task,
    CFStringRef entitlement,
    CFErrorRef *error);
}

static NSString *const kTLinkVPNDiagnosticsErrorDomain =
    @"com.tlinkauto.vpn.diagnostics";
static NSString *const kTLinkVPNProfileIdentifier =
    @"tlinkauto-managed-v1";
static NSString *const kTLinkVPNAPIEntitlement =
    @"com.apple.developer.networking.vpn.api";
static NSString *const kTLinkNetworkExtensionEntitlement =
    @"com.apple.developer.networking.networkextension";

NSString *TLinkVPNManagedProfileIdentifier(void)
{
    return kTLinkVPNProfileIdentifier;
}

static NSArray<NSString *> *TLinkVPNNormalizedEntitlementValues(CFTypeRef value)
{
    if (!value) return @[];
    id object = (__bridge id)value;
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    if ([object isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)object) {
            if ([item isKindOfClass:[NSString class]]) {
                [values addObject:item];
            }
        }
    } else if ([object isKindOfClass:[NSString class]]) {
        [values addObject:object];
    } else if ([object respondsToSelector:@selector(boolValue)] &&
               [object boolValue]) {
        [values addObject:@"true"];
    }
    return values;
}

static NSDictionary *TLinkVPNEntitlementProbe(void)
{
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) {
        return @{
            @"probe_source": @"sec_task_current_process",
            @"probe_available": @0,
            @"vpn_api_present": @0,
            @"vpn_api_values": @[],
            @"allow_vpn": @0,
            @"networkextension_present": @0,
            @"networkextension_values": @[],
            @"packet_tunnel_provider": @0,
        };
    }

    CFErrorRef vpnError = NULL;
    CFTypeRef vpnValue = SecTaskCopyValueForEntitlement(
        task,
        (__bridge CFStringRef)kTLinkVPNAPIEntitlement,
        &vpnError);
    NSArray<NSString *> *vpnValues =
        TLinkVPNNormalizedEntitlementValues(vpnValue);

    CFErrorRef networkExtensionError = NULL;
    CFTypeRef networkExtensionValue = SecTaskCopyValueForEntitlement(
        task,
        (__bridge CFStringRef)kTLinkNetworkExtensionEntitlement,
        &networkExtensionError);
    NSArray<NSString *> *networkExtensionValues =
        TLinkVPNNormalizedEntitlementValues(networkExtensionValue);

    NSDictionary *probe = @{
        @"probe_source": @"sec_task_current_process",
        @"probe_available": @1,
        @"vpn_api_present": @(vpnValue != NULL),
        @"vpn_api_values": vpnValues ?: @[],
        @"allow_vpn": @([vpnValues containsObject:@"allow-vpn"]),
        @"networkextension_present": @(networkExtensionValue != NULL),
        @"networkextension_values": networkExtensionValues ?: @[],
        @"packet_tunnel_provider":
            @([networkExtensionValues containsObject:@"packet-tunnel-provider"]),
    };

    if (vpnValue) CFRelease(vpnValue);
    if (vpnError) CFRelease(vpnError);
    if (networkExtensionValue) CFRelease(networkExtensionValue);
    if (networkExtensionError) CFRelease(networkExtensionError);
    CFRelease(task);
    return probe;
}

static NSDictionary *TLinkVPNFrameworkProbe(void)
{
    static dispatch_once_t onceToken;
    static BOOL frameworkLoaded = false;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",
            RTLD_LAZY | RTLD_LOCAL);
        frameworkLoaded = (handle != NULL);
    });

    BOOL managerClassAvailable = NSClassFromString(@"NEVPNManager") != Nil;
    return @{
        @"framework_loaded": @(frameworkLoaded),
        @"manager_class_available": @(managerClassAvailable),
        @"api_exercised": @0,
    };
}

static NSDictionary *TLinkVPNPrivateCompatibilityProbe(BOOL allowVPN)
{
    NSString *bundlePath =
        @"/System/Library/PreferenceBundles/VPNPreferences.bundle";
    if (!allowVPN) {
        return @{
            @"source": @"xxtouch_vpnconnectionstore_compatibility_probe",
            @"bundle_path": bundlePath,
            @"bundle_present": @([[NSFileManager defaultManager]
                fileExistsAtPath:bundlePath]),
            @"bundle_loaded": @0,
            @"store_class_available": @0,
            @"shared_store_available": @0,
            @"create_profile_selector": @0,
            @"list_profiles_selector": @0,
            @"delete_profile_selector": @0,
            @"select_profile_selector": @0,
            @"connection_selector": @0,
            @"candidate_ready": @0,
            @"mutating_api_exercised": @0,
            @"probe_skipped": @"allow_vpn_entitlement_missing",
            @"load_error": @"",
        };
    }

    static dispatch_once_t onceToken;
    static NSDictionary *probe = nil;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSError *loadError = nil;
        BOOL bundlePresent = bundle != nil;
        BOOL bundleLoaded = bundlePresent &&
            (bundle.loaded || [bundle loadAndReturnError:&loadError]);
        Class storeClass = NSClassFromString(@"VPNConnectionStore");
        BOOL sharedStore = storeClass &&
            [storeClass respondsToSelector:NSSelectorFromString(@"sharedInstance")];
        id store = nil;
        if (sharedStore) {
            store = ((id (*)(id, SEL))objc_msgSend)(
                (id)storeClass,
                NSSelectorFromString(@"sharedInstance"));
        }
        BOOL createProfile = store &&
            [store respondsToSelector:
                NSSelectorFromString(@"createVPNWithOptions:")];
        BOOL listProfiles = store &&
            ([store respondsToSelector:
                NSSelectorFromString(@"configurations")] ||
             [storeClass respondsToSelector:
                NSSelectorFromString(
                    @"createAllVPNByUserDefinedNamesDictionary")]);
        BOOL deleteProfile = store &&
            ([store respondsToSelector:
                NSSelectorFromString(@"deleteVPNWithServiceID:")] ||
             [store respondsToSelector:
                NSSelectorFromString(@"deleteVPNWithServiceID:withGrade:")]);
        BOOL selectProfile = store &&
            ([store respondsToSelector:NSSelectorFromString(@"setActiveVPNID:")] ||
             [store respondsToSelector:
                 NSSelectorFromString(@"setActiveVPNID:withGrade:")]);
        BOOL connection = store &&
            ([store respondsToSelector:NSSelectorFromString(@"currentConnection")] ||
             [store respondsToSelector:
                 NSSelectorFromString(@"currentConnectionWithGrade:")]);

        probe = @{
            @"source": @"xxtouch_vpnconnectionstore_compatibility_probe",
            @"bundle_path": bundlePath,
            @"bundle_present": @(bundlePresent),
            @"bundle_loaded": @(bundleLoaded),
            @"store_class_available": @(storeClass != Nil),
            @"shared_store_available": @(store != nil),
            @"create_profile_selector": @(createProfile),
            @"list_profiles_selector": @(listProfiles),
            @"delete_profile_selector": @(deleteProfile),
            @"select_profile_selector": @(selectProfile),
            @"connection_selector": @(connection),
            @"candidate_ready":
                @(bundleLoaded && store && createProfile && listProfiles &&
                  selectProfile && connection),
            @"mutating_api_exercised": @([[NSFileManager defaultManager]
                fileExistsAtPath:
                    @"/var/mobile/Library/TLinkauto/config/vpn-private-owned.plist"]),
            @"probe_skipped": @"",
            @"load_error": loadError.localizedDescription ?: @"",
        };
    });
    return probe;
}

NSDictionary *TLinkVPNDiagnosticsSnapshot(
    NSString *runtime,
    NSString *state,
    NSString *query,
    NSString *control,
    NSString *backend,
    NSString *broker,
    NSNumber *effectiveConnected)
{
    NSDictionary *entitlements = TLinkVPNEntitlementProbe();
    NSDictionary *framework = TLinkVPNFrameworkProbe();
    BOOL allowVPN = [entitlements[@"allow_vpn"] boolValue];
    NSDictionary *privateCompatibility =
        TLinkVPNPrivateCompatibilityProbe(allowVPN);
    BOOL managerAvailable = [framework[@"manager_class_available"] boolValue];
    NSString *preflight = (allowVPN && managerAvailable)
        ? @"candidate_unverified"
        : @"blocked_missing_entitlement_or_framework";
    uint64_t generatedAtMs =
        (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

    return @{
        @"contract_version": @1,
        @"vpn_contract_version": @1,
        @"diagnostics_version": @1,
        @"phase": @1,
        @"legacy_task": @59,
        @"runtime": runtime ?: @"unknown",
        @"state": state ?: @"unknown",
        @"query": query ?: @"unsupported",
        @"control": control ?: @"unsupported",
        @"backend": backend ?: @"none",
        @"broker": broker ?: @"not_implemented",
        @"broker_target": @"foreground_app_or_entitled_agent",
        @"broker_ready": @0,
        @"profile_scope": @"tlink_owned_only",
        @"profile_identifier": TLinkVPNManagedProfileIdentifier(),
        @"profile_state": @"not_probed",
        @"configuration_transport": @"local_ui_keychain_only",
        @"credentials_over_task59": @0,
        @"effective_connected_known": @(effectiveConnected != nil),
        @"effective_connected": effectiveConnected ?: [NSNull null],
        @"entitlement_probe_scope": @"current_process_only",
        @"entitlements": entitlements,
        @"network_extension": framework,
        @"private_compatibility": privateCompatibility,
        @"control_preflight": preflight,
        @"generated_at_ms": @(generatedAtMs),
    };
}

NSString *TLinkVPNDiagnosticsBase64(
    NSString *runtime,
    NSString *state,
    NSString *query,
    NSString *control,
    NSString *backend,
    NSString *broker,
    NSNumber *effectiveConnected,
    NSError **error)
{
    NSDictionary *snapshot = TLinkVPNDiagnosticsSnapshot(
        runtime,
        state,
        query,
        control,
        backend,
        broker,
        effectiveConnected);
    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot
                                                   options:0
                                                     error:&jsonError];
    if (!json || jsonError) {
        if (error) {
            *error = [NSError errorWithDomain:kTLinkVPNDiagnosticsErrorDomain
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"vpn_diagnostics_encode_failed"
            }];
        }
        return nil;
    }
    return [json base64EncodedStringWithOptions:0];
}
