// Frozen from 2b06a1f; compatibility oracle.
static NSString *zx_vpnBrokerRequest(NSString *command, NSString **error)
{
    int client = socket(AF_INET, SOCK_STREAM, 0);
    if (client < 0) {
        if (error) *error = @"vpn_broker_socket_failed";
        return nil;
    }
    struct timeval timeout = {30, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6014);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(client, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(client);
        if (error) *error = @"vpn_broker_unavailable";
        return nil;
    }

    NSString *line = [NSString stringWithFormat:@"%@\r\n", command ?: @""];
    NSData *request = [line dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *requestBytes = (const uint8_t *)request.bytes;
    NSUInteger remaining = request.length;
    while (remaining > 0) {
        ssize_t sent = send(client, requestBytes, remaining, 0);
        if (sent <= 0) {
            close(client);
            if (error) *error = @"vpn_broker_send_failed";
            return nil;
        }
        requestBytes += sent;
        remaining -= (NSUInteger)sent;
    }

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    while (response.length < 1024 * 1024) {
        ssize_t received = recv(client, buffer, sizeof(buffer), 0);
        if (received <= 0) break;
        [response appendBytes:buffer length:(NSUInteger)received];
        const uint8_t *bytes = (const uint8_t *)response.bytes;
        if (memchr(bytes, '\n', response.length)) break;
    }
    close(client);
    if (response.length == 0) {
        if (error) *error = @"vpn_broker_no_response";
        return nil;
    }

    NSString *raw = [[NSString alloc] initWithData:response
                                          encoding:NSUTF8StringEncoding];
    NSString *clean = [raw
        stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([clean hasPrefix:@"0;;"]) {
        return [clean substringFromIndex:3];
    }
    if ([clean hasPrefix:@"-1;;"]) {
        if (error) *error = [clean substringFromIndex:4];
        return nil;
    }
    if (error) *error = @"vpn_broker_invalid_response";
    return nil;
}

