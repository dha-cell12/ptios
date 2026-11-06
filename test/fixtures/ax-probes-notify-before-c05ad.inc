static BOOL TLinkNotifyFlag(const char *name)
{
    int token = 0;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state != 0;
}

