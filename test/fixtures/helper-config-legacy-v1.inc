// Frozen 2259bc0 config normalization before the metadata cache.
static NSDictionary *legacyHelperConfigSnapshot(NSString *configPath)
{
    NSMutableDictionary *snapshot = [@{
        @"configPath": configPath ?: @"",
        @"configValid": @NO,
        @"enabled": @NO,
        @"runtimeDefault": @NO,
        @"allowAdminRPC": @NO,
        @"error": @"",
    } mutableCopy];
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        snapshot[@"error"] = @"missing_or_empty_config";
        return snapshot;
    }
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        snapshot[@"error"] = error.localizedDescription ?: @"config_parse_failed";
        return snapshot;
    }
    NSDictionary *dict = (NSDictionary *)obj;
    snapshot[@"configValid"] = @YES;
    id enabled = dict[@"javascript_helper_runtime_enabled"] ?: dict[@"enable_js_helper_execution"];
    id runtimeDefault = dict[@"javascript_helper_runtime_default"];
    id allowAdmin = dict[@"javascript_helper_allow_admin_rpc"];
    snapshot[@"enabled"] = @([enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue]);
    snapshot[@"runtimeDefault"] = @([runtimeDefault respondsToSelector:@selector(boolValue)] && [runtimeDefault boolValue]);
    snapshot[@"allowAdminRPC"] = @([allowAdmin respondsToSelector:@selector(boolValue)] && [allowAdmin boolValue]);
    return snapshot;
}

