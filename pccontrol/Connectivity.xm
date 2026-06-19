#include <objc/message.h>
#include <dlfcn.h>

#import "Connectivity.h"

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
    // VPN control typically requires entitlements. Provide a best-effort stub.
    int action = 0, value = 0;
    if (!zx_parseActionValue(eventData, &action, &value, error)) return nil;

    if (error) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;VPN control not implemented on this build.\r\n"}];
    }
    return nil;
}
