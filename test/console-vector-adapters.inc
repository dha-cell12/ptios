static size_t ConsoleVectorCapacity(size_t capacity){return consoleVectorOverride?std::min(capacity,consoleVectorOverride):capacity;}
static NSMutableData *ConsoleJoinedData(NSUInteger total){++consoleJoinedCount;assert(total<=TLinkConsoleLogVectorIO::MaxBytes);return [NSMutableData dataWithCapacity:total];}
static NSMutableData *ConsoleBeforeJoinedData(){++consoleBeforeJoinedCount;return [NSMutableData data];}
static ssize_t ConsoleWriteVectors(int fd,const struct iovec *vectors,int count){
    ++consoleWrites;++consoleVectorCalls;
    bool latest=false;
    {std::lock_guard<std::mutex> guard(consoleDescriptorMutex);const auto found=consoleDescriptors.find(fd);assert(found!=consoleDescriptors.end());latest=found->second;}
    if(consoleFault==2||consoleVectorMode==5)throw std::runtime_error("vector write failed");
    if((consoleFault==5&&latest)||consoleVectorMode==6)[NSException raise:@"LogFixture" format:@"vector write failed"];
    assert(count>0&&size_t(count)<=TLinkConsoleLogVectorCapacity());
    size_t offered=0;
    for(int n=0;n<count;++n){
        offered+=vectors[n].iov_len;
        if(!consoleExpectedSpans.empty()){
            bool found=false;const uintptr_t start=(uintptr_t)vectors[n].iov_base;
            for(const auto &span:consoleExpectedSpans){const uintptr_t base=(uintptr_t)span.bytes;if(start>=base&&start-base<=span.length&&vectors[n].iov_len<=span.length-(start-base))found=true;}
            assert(found);
        }
    }
    if(consoleVectorMode==3)return 0;
    if(consoleVectorMode==4)return ssize_t(offered+1);
    if(consoleVectorMode==1&&consoleVectorCalls==1){errno=EINTR;return -1;}
    if(consoleVectorMode==2&&consoleVectorCalls>1){errno=EIO;return -1;}
    if(consoleVectorMode==1||consoleVectorMode==2){
        std::array<struct iovec,TLinkConsoleLogVectorIO::MaxVectors> shortVectors{};
        size_t left=7;int used=0;
        for(int n=0;n<count&&left;++n){shortVectors[used]=vectors[n];shortVectors[used].iov_len=std::min(left,vectors[n].iov_len);left-=shortVectors[used].iov_len;++used;}
        return ::writev(fd,shortVectors.data(),used);
    }
    return ::writev(fd,vectors,count);
}
