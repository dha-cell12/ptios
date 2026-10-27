// Frozen aca0719 app paths compatibility oracle.
static NSString *zx_pathFromURLLike(id urlLike)
{
    if (!urlLike || urlLike == (id)kCFNull) {
        return @"";
    }
    if ([urlLike isKindOfClass:[NSURL class]]) {
        return [(NSURL *)urlLike path] ?: @"";
    }
    if ([urlLike respondsToSelector:@selector(path)]) {
        NSString *p = ((NSString *(*)(id, SEL))objc_msgSend)(urlLike, @selector(path));
        return p ?: @"";
    }
    return @"";
}

