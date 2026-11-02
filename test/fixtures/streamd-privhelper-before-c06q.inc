static int TLinkRunPrivhelper(NSArray<NSString *> *arguments, int timeoutMs)
{
    if (arguments.count == 0) return -100;
    NSString *path = TLinkPrivhelperPath();
    if (path.length == 0) return -101;
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
    for (NSUInteger i = 0; i < argc; i++) {
        if (argv[i]) free(argv[i]);
    }
    free(argv);
    if (rc != 0 || pid <= 0) return rc != 0 ? rc : -103;

    int status = 0;
    int loops = timeoutMs > 0 ? timeoutMs / 100 : 30;
    if (loops < 1) loops = 1;
    for (int i = 0; i < loops; i++) {
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return -104;
        }
        if (w < 0) return -105;
        usleep(100 * 1000);
    }
    kill(pid, SIGKILL);
    waitpid(pid, &status, 0);
    return -106;
}

