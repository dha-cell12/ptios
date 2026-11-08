        NSMutableData *data = [NSMutableData data];
        const int fd=_fd;
        const auto input=TLinkJSFileIO::ReadInto(requested,
            [data](size_t used,size_t amount)->uint8_t * {
                [data setLength:used+amount];
                uint8_t *base=(uint8_t *)data.mutableBytes;
                return base?base+used:nullptr;
            },[fd](uint8_t *bytes,size_t amount)->int64_t{return ::read(fd,bytes,amount);});
        if(input.error)return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s",input.error,strerror(input.error)],self.path);
        [data setLength:input.bytes];
