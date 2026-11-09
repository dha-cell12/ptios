struct TLinkConsoleLogEntry {
    NSData *data;
    NSString *runPath,*latestPath,*runId,*systemLevel,*systemMessage;
    std::shared_ptr<TLinkConsoleLogPermit> permit;
    TLinkConsoleLogEntry(NSData *value,NSString *run,NSString *latest,NSString *identifier,NSString *level,NSString *message,std::shared_ptr<TLinkConsoleLogPermit> charge)
        :data(value),runPath(run),latestPath(latest),runId(identifier),systemLevel(level),systemMessage(message),permit(std::move(charge)){}
};

