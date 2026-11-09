@interface ConsolePermitWitness:NSObject {
@public std::shared_ptr<TLinkConsoleLogBudget> budget;
}
@end
static unsigned consoleWitnessDrops=0;
@implementation ConsolePermitWitness
- (void)dealloc{assert(budget&&budget->snapshot().pending==1);++consoleWitnessDrops;}
@end
static void consoleRunRetainedJobs(){
    @autoreleasepool {
        NSArray *jobs=[consoleRetainedJobs copy];[consoleRetainedJobs removeAllObjects];
        for(id value in jobs){dispatch_block_t block=(dispatch_block_t)value;block();}
    }
}
static void consoleRetireFirstJob(){
    @autoreleasepool {
        dispatch_block_t block=(dispatch_block_t)consoleRetainedJobs[0];[consoleRetainedJobs removeObjectAtIndex:0];block();
    }
}
static void consoleScheduleRuntimeCases(NSString *root){
    puts("Root console transactions: actual publication/queue/ticket retirement, stale jobs and finish drain");
    consoleRetainedJobs=[NSMutableArray array];
    for(unsigned kind=0;kind<2;++kind){
        TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"publication-%u",kind]],@"publication");
        if(kind){[logger holdWriter];[logger appendConsoleLogWithLevel:@"log" message:@"already-published"];}
        consolePublicationFault=true;[logger appendConsoleLogWithLevel:@"log" message:@"allocation-refused"];consolePublicationFault=false;
        assert([[logger currentConsoleLogStats][@"pendingLines"] intValue]==(int)kind);
        [logger appendConsoleLogWithLevel:@"log" message:@"allocation-recovered"];
        if(kind)[logger resumeWriter];
        [logger finishConsoleLogging];NSDictionary *stats=[logger currentConsoleLogStats];
        assert([stats[@"pendingLines"] intValue]==0&&[stats[@"dropped"] intValue]==1&&[stats[@"accepted"] intValue]==(int)kind+1);
        assert(![consoleText(logger.runPath) containsString:@" allocation-refused\n"]&&[consoleText(logger.runPath) containsString:@" allocation-recovered\n"]);consoleTakeSystemRecords();
    }
    for(unsigned fault:{1U,2U,3U,5U,6U}){
        TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"enqueue-%u",fault]],@"enqueue");
        @autoreleasepool {consoleEnqueueFault=fault;[logger appendConsoleLogWithLevel:@"log" message:@"discarded-message"];}
        consoleEnqueueFault=0;
        NSDictionary *before=[logger currentConsoleLogStats];assert([before[@"pendingLines"] intValue]==0&&[before[@"dropped"] intValue]==1);
        [logger appendConsoleLogWithLevel:@"log" message:@"recovered-message"];[logger finishConsoleLogging];
        assert(![consoleText(logger.runPath) containsString:@" discarded-message\n"]&&[consoleText(logger.runPath) containsString:@" recovered-message\n"]);
        NSString *settled=consoleText(logger.runPath);consoleRunRetainedJobs();assert([settled isEqual:consoleText(logger.runPath)]);
        assert([[logger currentConsoleLogStats][@"pendingLines"] intValue]==0);consoleTakeSystemRecords();
    }
    TLinkJSRuntimeCore *abandoned=consoleStart([root stringByAppendingPathComponent:@"abandoned-job"],@"abandoned");
    consoleEnqueueFault=4;
    for(unsigned n=0;n<8;++n){[abandoned appendConsoleLogWithLevel:@"log" message:@"abandoned-message"];}
    assert(consoleRetainedJobs.count==1&&[[abandoned currentConsoleLogStats][@"pendingLines"] intValue]==8);
    @autoreleasepool {[consoleRetainedJobs removeAllObjects];}
    consoleEnqueueFault=0;assert([[abandoned currentConsoleLogStats][@"pendingLines"] intValue]==0&&[[abandoned currentConsoleLogStats][@"dropped"] intValue]==8);
    [abandoned finishConsoleLogging];assert(![consoleText(abandoned.runPath) containsString:@" abandoned-message\n"]);consoleTakeSystemRecords();
    TLinkJSRuntimeCore *stale=consoleStart([root stringByAppendingPathComponent:@"stale-jobs"],@"stale");
    consoleEnqueueFault=5;@autoreleasepool{[stale appendConsoleLogWithLevel:@"log" message:@"failed-old-job"];}
    consoleEnqueueFault=4;[stale appendConsoleLogWithLevel:@"log" message:@"held-current-job"];
    assert(consoleRetainedJobs.count==2);consoleRetireFirstJob();
    assert([[stale currentConsoleLogStats][@"pendingLines"] intValue]==1);
    [stale finishConsoleLogging];assert([[stale currentConsoleLogStats][@"pendingLines"] intValue]==0&&[consoleText(stale.runPath) containsString:@" held-current-job\n"]);
    [stale beginConsoleLogging];[stale appendConsoleLogWithLevel:@"log" message:@"next-run-job"];
    assert(consoleRetainedJobs.count==2);consoleRetireFirstJob();assert([[stale currentConsoleLogStats][@"pendingLines"] intValue]==1);
    [stale finishConsoleLogging];consoleEnqueueFault=0;NSString *finished=consoleText(stale.runPath);consoleRunRetainedJobs();
    assert([finished isEqual:consoleText(stale.runPath)]&&[finished containsString:@" next-run-job\n"]&&![finished containsString:@" failed-old-job\n"]);
    consoleTakeSystemRecords();
    __weak TLinkJSRuntimeCore *weakOwner=nil;consoleEnqueueFault=4;
    @autoreleasepool {
        TLinkJSRuntimeCore *temporary=consoleStart([root stringByAppendingPathComponent:@"ticket-owner"],@"ticket-owner");weakOwner=temporary;
        [temporary appendConsoleLogWithLevel:@"log" message:@"owner-retained"];temporary=nil;
    }
    @autoreleasepool {assert(weakOwner!=nil&&consoleRetainedJobs.count==1);}
    @autoreleasepool {[consoleRetainedJobs removeAllObjects];}
    consoleEnqueueFault=0;assert(weakOwner==nil);
    auto budget=std::make_shared<TLinkConsoleLogBudget>();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool {
            ConsolePermitWitness *witness=[ConsolePermitWitness new];witness->budget=budget;auto permit=TLinkConsoleLogPermit::acquire(budget);
            auto entry=std::make_shared<TLinkConsoleLogEntry>(nil,nil,nil,nil,nil,(NSString *)witness,permit);permit.reset();witness=nil;
            assert(budget->snapshot().pending==1);entry.reset();assert(budget->snapshot().pending==0);
        }
    }
    assert(consoleWitnessDrops==128&&consoleRetainedJobs.count==0&&consoleLive==0);consoleRetainedJobs=nil;
    puts("Root console transactions passed: NS/C++ enqueue before/after copy, discard/retained jobs, rollback and recovery, abandoned batch release, same-run and cross-run stale fencing, forced terminal drain without replay and 128 actual payload-before-permit retirements. Device qualification pending.");
}
