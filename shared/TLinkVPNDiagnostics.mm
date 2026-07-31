#import "TLinkVPNDiagnostics.h"

#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdint.h>

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
