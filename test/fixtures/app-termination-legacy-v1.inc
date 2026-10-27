// Frozen 1e5c795 app kill compatibility oracle.
static BOOL sendTerminationToApp(SBApplication *app)
{
    if (!app)
    {
        return false;
    }

    SEL killSelector = NSSelectorFromString(@"kill");
    if ([app respondsToSelector:killSelector])
    {
        ((void (*)(id, SEL))objc_msgSend)(app, killSelector);
        return true;
    }

    SEL terminateSelector = NSSelectorFromString(@"terminate");
    if ([app respondsToSelector:terminateSelector])
    {
        ((void (*)(id, SEL))objc_msgSend)(app, terminateSelector);
        return true;
    }

    return false;
}

