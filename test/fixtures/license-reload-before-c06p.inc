static NSString *SCLicenseRootfullReloadRequest(void)
{
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) return @"socket_create_failed";

    struct timeval timeout = {2, 0};
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(descriptor);
        return @"streamd_connect_failed";
    }

    const char request[] = "76reload\r\n";
    ssize_t written = send(descriptor, request, sizeof(request) - 1, 0);
    if (written != (ssize_t)(sizeof(request) - 1)) {
        close(descriptor);
        return @"streamd_send_failed";
    }

    char response[8192];
    memset(response, 0, sizeof(response));
    ssize_t received = recv(descriptor, response, sizeof(response) - 1, 0);
    close(descriptor);
    if (received <= 0) return @"streamd_no_response";
    response[received] = '\0';
    NSString *value = [NSString stringWithUTF8String:response] ?: @"streamd_invalid_response";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
