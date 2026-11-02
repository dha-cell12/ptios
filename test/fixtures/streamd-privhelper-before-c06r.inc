static int TLinkRunPrivhelper(NSArray<NSString *> *arguments, int timeoutMs)
{
    if (arguments.count == 0) return -100;
    NSString *path = TLinkPrivhelperPath();
    if (path.length == 0) return -101;
    // BEGIN bounded streamd helper owner.
    TLinkVPNHelperChild::Owner child;
    if (!child.admitted()) return -107;
    if (!child.ready()) return -108;
    // END bounded streamd helper owner.
    const char *cpath = [path fileSystemRepresentation];

    NSUInteger argc = arguments.count + 2;
    char **argv = (char **)calloc(argc, sizeof(char *));
    if (!argv) return -102;
    argv[0] = strdup(cpath);
    BOOL allocFailed = argv[0] == NULL;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *arg = arguments[i] ?: @"";
        argv[i + 1] = strdup([arg UTF8String] ?: "");
        if (!argv[i + 1]) allocFailed = YES;
    }
    argv[argc - 1] = NULL;
    if (allocFailed) {
        for (NSUInteger i = 0; i < argc; i++) {
            if (argv[i]) free(argv[i]);
        }
        free(argv);
        return -102;
    }

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, NULL, argv, environ);
    if (rc == 0 && pid > 0) child.adopted(pid);
    for (NSUInteger i = 0; i < argc; i++) {
        if (argv[i]) free(argv[i]);
    }
    free(argv);
    if (rc != 0 || pid <= 0) return rc != 0 ? rc : -103;

    // BEGIN bounded streamd helper wait.
    const unsigned requested = timeoutMs > 0 ? static_cast<unsigned>(std::max(1, timeoutMs / 100)) * 100U : 3000U;
    const auto result = child.wait(std::min(requested, 30000U));
    if (result.reason == TLinkVPNHelperChild::Reason::Timeout) return -106;
    if (result.reason != TLinkVPNHelperChild::Reason::Finished || !result.retired) return -105;
    if (WIFEXITED(result.status)) return WEXITSTATUS(result.status);
    if (WIFSIGNALED(result.status)) return 128 + WTERMSIG(result.status);
    return -104;
    // END bounded streamd helper wait.
}

