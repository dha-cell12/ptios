// Frozen aed36da radio compatibility oracle (unchanged in C02b37).
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

