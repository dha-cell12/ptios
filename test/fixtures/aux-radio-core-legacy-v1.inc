// Frozen 4c7e249 airplane/cellular compatibility oracle.
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

