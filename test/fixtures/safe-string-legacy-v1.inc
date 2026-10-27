// Frozen 68cd857 listBundles compatibility oracle.
static NSString *zx_safeString(id v)
{
    if (!v || v == (id)kCFNull) {
        return @"";
    }
    if ([v isKindOfClass:[NSString class]]) {
        return (NSString *)v;
    }
    return [v description] ?: @"";
}

