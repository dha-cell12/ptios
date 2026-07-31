#include <objc/message.h>
#include <dlfcn.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#import "Connectivity.h"
#import "../shared/TLinkVPNDiagnostics.h"

static BOOL zx_parseActionValue(UInt8 *eventData, int *outAction, int *outValue, NSError **error)
{
    NSString *raw = [NSString stringWithFormat:@"%s", eventData ?: (UInt8*)""];
    NSArray *parts = [raw componentsSeparatedByString:@";;"];
    if ([parts count] < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing action.\r\n"}];
        }
        return false;
    }
    int action = [parts[0] intValue];
    int value = 0;
    if (action == 1) {
        if ([parts count] < 2) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing value.\r\n"}];
            }
            return false;
        }
        value = [parts[1] intValue] ? 1 : 0;
    }
    if (outAction) *outAction = action;
    if (outValue) *outValue = value;
    return true;
}

static id zx_sharedInstance(Class cls)
{
    if (!cls) return nil;
    SEL s1 = NSSelectorFromString(@"sharedInstance");
    if ([cls respondsToSelector:s1]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, s1);
    }
    SEL s2 = NSSelectorFromString(@"sharedManager");
    if ([cls respondsToSelector:s2]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, s2);
    }
    return nil;
}

static BOOL zx_getBool(id obj, const char *selName, BOOL *out)
{
    if (!obj) return false;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return false;
    BOOL v = ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
    if (out) *out = v;
    return true;
}

static BOOL zx_setBool(id obj, const char *selName, BOOL value)
{
    if (!obj) return false;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return false;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
    return true;
}

static NSString *zx_boolString(BOOL v) { return v ? @"1" : @"0"; }

static NSString *zx_vpnBrokerRequest(NSString *command, NSString **error)
{
    int client = socket(AF_INET, SOCK_STREAM, 0);
    if (client < 0) {
        if (error) *error = @"vpn_broker_socket_failed";
        return nil;
    }
    struct timeval timeout = {30, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6014);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(client, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(client);
        if (error) *error = @"vpn_broker_unavailable";
        return nil;
    }

    NSString *line = [NSString stringWithFormat:@"%@\r\n", command ?: @""];
    NSData *request = [line dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *requestBytes = (const uint8_t *)request.bytes;
    NSUInteger remaining = request.length;
    while (remaining > 0) {
        ssize_t sent = send(client, requestBytes, remaining, 0);
        if (sent <= 0) {
            close(client);
            if (error) *error = @"vpn_broker_send_failed";
            return nil;
        }
        requestBytes += sent;
        remaining -= (NSUInteger)sent;
    }

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    while (response.length < 1024 * 1024) {
        ssize_t received = recv(client, buffer, sizeof(buffer), 0);
        if (received <= 0) break;
        [response appendBytes:buffer length:(NSUInteger)received];
        const uint8_t *bytes = (const uint8_t *)response.bytes;
        if (memchr(bytes, '\n', response.length)) break;
    }
    close(client);
    if (response.length == 0) {
        if (error) *error = @"vpn_broker_no_response";
        return nil;
    }

    NSString *raw = [[NSString alloc] initWithData:response
                                          encoding:NSUTF8StringEncoding];
    NSString *clean = [raw
        stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([clean hasPrefix:@"0;;"]) {
        return [clean substringFromIndex:3];
    }
    if ([clean hasPrefix:@"-1;;"]) {
        if (error) *error = [clean substringFromIndex:4];
        return nil;
    }
    if (error) *error = @"vpn_broker_invalid_response";
    return nil;
}

NSString* wifiTaskFromRawData(UInt8 *eventData, NSError **error)
{
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    // Try SBWiFiManager (common on many iOS versions)
    Class cls = NSClassFromString(@"SBWiFiManager");
    id mgr = zx_sharedInstance(cls);

    BOOL enabled = NO;
    if (!mgr) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;SBWiFiManager unavailable.\r\n"}];
        return nil;
    }

    if (action == 1) {
        // set
        if (!(zx_setBool(mgr, "setWiFiEnabled:", (BOOL)value) || zx_setBool(mgr, "setWifiEnabled:", (BOOL)value))) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to set Wi-Fi state.\r\n"}];
            return nil;
        }
    }

    if (!(zx_getBool(mgr, "wiFiEnabled", &enabled) || zx_getBool(mgr, "wifiEnabled", &enabled) || zx_getBool(mgr, "isWiFiEnabled", &enabled))) {
        // Fallback: assume requested state
        enabled = (BOOL)value;
    }
    return zx_boolString(enabled);
}

NSString* bluetoothTaskFromRawData(UInt8 *eventData, NSError **error)
{
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    // BluetoothManager in /System/Library/PrivateFrameworks/BluetoothManager.framework
    Class cls = NSClassFromString(@"BluetoothManager");
    id mgr = zx_sharedInstance(cls);
    if (!mgr) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;BluetoothManager unavailable.\r\n"}];
        return nil;
    }

    if (action == 1) {
        if (!(zx_setBool(mgr, "setPowered:", (BOOL)value) || zx_setBool(mgr, "setEnabled:", (BOOL)value))) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to set Bluetooth state.\r\n"}];
            return nil;
        }
    }

    BOOL enabled = NO;
    if (!(zx_getBool(mgr, "powered", &enabled) || zx_getBool(mgr, "enabled", &enabled) || zx_getBool(mgr, "isEnabled", &enabled))) {
        enabled = (BOOL)value;
    }
    return zx_boolString(enabled);
}

NSString* airplaneTaskFromRawData(UInt8 *eventData, NSError **error)
{
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    // Try RadiosPreferences (seen on many iOS builds)
    Class cls = NSClassFromString(@"RadiosPreferences");
    id pref = zx_sharedInstance(cls);

    // Try alternative controller
    if (!pref) {
        Class c2 = NSClassFromString(@"SBAirplaneModeController");
        pref = zx_sharedInstance(c2);
    }

    if (!pref) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Airplane mode controller unavailable.\r\n"}];
        return nil;
    }

    if (action == 1) {
        if (!(zx_setBool(pref, "setAirplaneMode:", (BOOL)value) || zx_setBool(pref, "setAirplaneModeEnabled:", (BOOL)value))) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to set Airplane mode.\r\n"}];
            return nil;
        }
    }

    BOOL enabled = NO;
    if (!(zx_getBool(pref, "airplaneMode", &enabled) || zx_getBool(pref, "airplaneModeEnabled", &enabled) || zx_getBool(pref, "isAirplaneModeEnabled", &enabled))) {
        enabled = (BOOL)value;
    }
    return zx_boolString(enabled);
}

NSString* cellularDataTaskFromRawData(UInt8 *eventData, NSError **error)
{
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    // Best-effort via RadiosPreferences if present.
    Class cls = NSClassFromString(@"RadiosPreferences");
    id pref = zx_sharedInstance(cls);
    if (!pref) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Cellular data control unavailable.\r\n"}];
        return nil;
    }

    if (action == 1) {
        if (!zx_setBool(pref, "setCellularDataEnabled:", (BOOL)value)) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to set Cellular Data.\r\n"}];
            return nil;
        }
    }

    BOOL enabled = NO;
    if (!zx_getBool(pref, "cellularDataEnabled", &enabled)) {
        enabled = (BOOL)value;
    }
    return zx_boolString(enabled);
}

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
