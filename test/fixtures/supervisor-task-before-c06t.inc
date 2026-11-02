- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)timeoutSec
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return nil;

    struct timeval tv;
    tv.tv_sec = timeoutSec > 0 ? timeoutSec : 1;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return nil;
    }

    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    const char *bytes = [payload UTF8String];
    send(sock, bytes, strlen(bytes), 0);

    NSMutableData *data = [NSMutableData data];
    char buf[2048];
    while (true) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
        if (memchr(buf, '\n', (size_t)n)) break;
        if (data.length > 64 * 1024) break;
    }
    close(sock);

    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

