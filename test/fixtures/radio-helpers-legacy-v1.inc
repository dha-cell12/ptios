// Frozen aed36da radio compatibility oracle (unchanged in C02b37).
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

