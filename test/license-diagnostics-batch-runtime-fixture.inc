// Actual and complete immediate-predecessor coordinators. Only UI/reload workers
// and license-manager effects are controlled; diagnostics use real plist IO.
#define BATCH_PROPERTIES \
@property NSUInteger reloads; \
@property(nonatomic,strong) NSMutableArray *reasons;
#define BATCH_OVERRIDES \
- (uint64_t)nowMilliseconds{return 1000000;} \
- (void)requestDaemonReload{++_reloads;} \
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason{if(!_reasons)_reasons=[NSMutableArray array];[_reasons addObject:reason?:@""];} \
- (void)drainDecisions{dispatch_sync(self.refreshDecisionQueue,^{});}
@interface BatchCurrentLifecycle:SCLicenseLifecycleCoordinator
BATCH_PROPERTIES
- (void)drainDecisions;
@end
@implementation BatchCurrentLifecycle
BATCH_OVERRIDES
@end
@interface BatchBeforeLifecycle:SCBeforeBatchLifecycleCoordinator
BATCH_PROPERTIES
- (void)drainDecisions;
@end
@implementation BatchBeforeLifecycle
BATCH_OVERRIDES
@end
#undef BATCH_PROPERTIES
#undef BATCH_OVERRIDES
@interface BatchFixtureManager:FixtureManager
@property BOOL terminalSuccess;
@property NSUInteger terminalCalls;
@property unsigned writeFaultOnReply;
@end
@implementation BatchFixtureManager
- (void)activateLicenseKey:(NSString *)key intent:(NSString *)intent completion:(SCLicenseLifecycleCompletion)completion{
    (void)key;(void)intent;++_terminalCalls;batchWriteFault=_writeFaultOnReply;completion(_terminalSuccess,@"terminal");
}
- (void)deactivateLeaseWithCompletion:(SCLicenseLifecycleCompletion)completion{
    ++_terminalCalls;batchWriteFault=_writeFaultOnReply;completion(_terminalSuccess,@"terminal");
}
@end
static unsigned batchReads(bool before){return before?beforeBatchDiagnosticReads.load():currentDiagnosticReads.load();}
static unsigned batchWrites(bool before){return before?beforeBatchDiagnosticWrites.load():currentDiagnosticWrites.load();}
static NSString *batchPath(bool before){return before?beforeBatchPath:currentPath;}
static id batchCoordinator(bool before){return before?(id)[BatchBeforeLifecycle new]:(id)[BatchCurrentLifecycle new];}
static void batchPrepare(bool before){assert(([@{@"untouched":@7,@"consecutive_failures":@0,@"next_attempt_at_ms":@0} writeToFile:batchPath(before) atomically:YES]));}
static NSDictionary *batchTerminal(bool before,unsigned operation,bool success){
    batchPrepare(before);BatchFixtureManager *manager=[BatchFixtureManager new];FixtureManager *templateManager=managerFor(0);
    manager.before=templateManager.before;manager.after=templateManager.after;manager.terminalSuccess=success;
    id value=batchCoordinator(before);[value setValue:manager forKey:@"manager"];
    auto result=std::make_shared<Reply>();auto notifications=std::make_shared<std::atomic<unsigned>>(0);
    NSString *name=before?SCBeforeBatchLifecycleDidChangeNotification:SCLicenseLifecycleDidChangeNotification;
    id observer=[[NSNotificationCenter defaultCenter] addObserverForName:name object:value queue:nil usingBlock:^(NSNotification *note){(void)note;++*notifications;}];
    const unsigned reads=batchReads(before),writes=batchWrites(before);
    if(operation==0){
        [value refreshForTrigger:@"batch" force:YES completion:completionFor(result)];
        await([&]{return manager.requests==1;});manager.reply(success,@"terminal");
    }else if(operation==1)[value activateLicenseKey:@"fixture" intent:@"fixture" completion:completionFor(result)];
    else [value deactivateWithCompletion:completionFor(result)];
    await([&]{return result->calls.load()==1;});[value drainDecisions];
    auto drained=std::make_shared<std::atomic<bool>>(false);dispatch_async(dispatch_get_main_queue(), ^{*drained=true;});
    await([&]{return drained->load();});
    assert(![value isRequestInFlight]&&result->success==success);
    assert(batchReads(before)-reads==(before?(success?4U:3U):2U));
    assert(batchWrites(before)-writes==(before?(success?4U:3U):2U));
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:batchPath(before)];
    NSDictionary *snapshot=@{@"state":state,@"message":result->message?:@"",@"success":@(result->success),
        @"reasons":[value reasons]?:@[],@"reloads":@([value reloads]),@"notifications":@(notifications->load()),
        @"manager_reads":@(manager.localReads),@"requests":@(manager.requests),@"mutations":@(manager.terminalCalls)};
    manager.reply=nil;return snapshot;
}
static void batchBasicCases(){
    for(unsigned cycle=0;cycle<8;++cycle){
        for(unsigned operation=0;operation<3;++operation){
            for(bool success:{false,true}){
                @autoreleasepool {
                    NSDictionary *before=batchTerminal(true,operation,success),*now=batchTerminal(false,operation,success);
                    if(![before isEqual:now])fprintf(stderr,"Diagnostics terminal mismatch: op=%u success=%d before=%.2048s now=%.2048s\n",operation,success,[before.description UTF8String]?:"?",[now.description UTF8String]?:"?");
                    assert([before isEqual:now]);
                }
            }
        }
    }
    batchPrepare(false);BatchCurrentLifecycle *value=[BatchCurrentLifecycle new];
    const unsigned reads=batchReads(false),writes=batchWrites(false);
    [value performDiagnosticsBatch:^{}];assert(batchReads(false)==reads&&batchWrites(false)==writes);
    [value performDiagnosticsBatch:^{
        [value updateDiagnostics:@{@"first":@1}];
        NSMutableString *message=[@"original" mutableCopy];NSMutableData *bytes=[NSMutableData dataWithBytes:"a" length:1];
        [value updateDiagnostics:@{@"message":message,@"bytes":bytes}];
        [message setString:@"mutated"];[bytes appendBytes:"b" length:1];
        [value performDiagnosticsBatch:^{[value updateDiagnostics:@{@"second":@2}];}];
        NSMutableDictionary *event=[@{@"id":@(-1)} mutableCopy];
        [value appendRefreshHistoryEvent:event];event[@"id"]=@999;
        [value updateDiagnostics:@{@"invalid_plist":[NSNull null]}];
        NSDictionary *visible=[value diagnostics];assert([visible[@"first"] intValue]==1&&[visible[@"second"] intValue]==2);
        assert([visible[@"message"] isEqual:@"original"]&&[visible[@"bytes"] length]==1&&!visible[@"invalid_plist"]);
        ((NSMutableDictionary *)visible)[@"first"]=@99;assert([[[value diagnostics] objectForKey:@"first"] intValue]==1);
        assert([visible[@"refresh_history"][0][@"id"] intValue]==-1);
        assert(batchWrites(false)==writes);
        for(unsigned n=0;n<60;++n)[value appendRefreshHistoryEvent:@{@"id":@(n)}];
    }];
    assert(batchReads(false)==reads+1&&batchWrites(false)==writes+1&&!value.diagnosticsBatchActive&&!value.diagnosticsBatchState);
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:currentPath];NSArray *history=state[@"refresh_history"];
    assert(history.count==20&&[history.firstObject[@"id"] unsignedIntValue]==40&&[history.lastObject[@"id"] unsignedIntValue]==59);
    // No cache survives a group: an external replacement is merged on the next read.
    assert(([@{@"external":@9} writeToFile:currentPath atomically:YES]));
    [value updateDiagnostics:@{@"after":@3}];state=[NSDictionary dictionaryWithContentsOfFile:currentPath];
    assert([state[@"external"] intValue]==9&&[state[@"after"] intValue]==3&&!state[@"first"]);
}
static void batchSnapshotCases(){
    NSDictionary *expected=nil;
    for(bool before:{true,false}){
        batchPrepare(before);id value=batchCoordinator(before);
        NSMutableString *text=[@"ảnh 测试" mutableCopy];NSMutableData *bytes=[NSMutableData dataWithBytes:"a\0b" length:3];
        NSMutableDictionary *nested=[@{@"text":text} mutableCopy];
        dispatch_block_t body=^{
            [value updateDiagnostics:@{@"nested":@[nested],@"bytes":bytes,@"unsigned":@(UINT64_MAX),@"date":[NSDate dateWithTimeIntervalSince1970:1.25]}];
            [text setString:@"changed"];nested[@"extra"]=@YES;[bytes appendBytes:"c" length:1];
            [value updateDiagnostics:@{@"terminal":@YES}];
        };
        if(before)body();else [value performDiagnosticsBatch:body];
        NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:batchPath(before)];
        if(before)expected=state;else assert([expected isEqual:state]);
    }
}
static void batchFaultCases(){
    for(unsigned fault=1;fault<=2;++fault){
        batchPrepare(false);BatchCurrentLifecycle *value=[BatchCurrentLifecycle new];bool caught=false;
        @autoreleasepool {
            @try {try {
                [value performDiagnosticsBatch:^{
                    [value updateDiagnostics:@{@"committed":@1}];
                    [value updateDiagnostics:nil refreshHistoryEvent:nil stateMutation:^(NSMutableDictionary *state){
                        state[@"not_committed"]=@1;
                        if(fault==1)[NSException raise:@"DiagnosticsBatch" format:@"mutation"];
                        throw std::runtime_error("mutation");
                    }];
                }];
            }catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"DiagnosticsBatch"]);caught=true;}
        }
        NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:currentPath];
        assert(caught&&[state[@"committed"] intValue]==1&&!state[@"not_committed"]&&!value.diagnosticsBatchActive&&!value.diagnosticsBatchState);
        [value updateDiagnostics:@{@"recovered":@1}];
    }
    for(unsigned site=0;site<2;++site){
        for(unsigned fault=1;fault<=(site==0?2U:3U);++fault){
            batchPrepare(false);BatchCurrentLifecycle *value=[BatchCurrentLifecycle new];bool caught=false;
            if(site==0)batchReadFault=fault;else batchWriteFault=fault;
            @autoreleasepool {
                @try {try {[value performDiagnosticsBatch:^{[value updateDiagnostics:@{@"failed":@1}];}];}
                    catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"DiagnosticsBatch"]);caught=true;}
            }
            batchReadFault=batchWriteFault=0;
            assert(caught==(site==0));
            assert(!value.diagnosticsBatchActive&&!value.diagnosticsBatchState);
            NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:currentPath];assert(!state[@"failed"]);
            [value updateDiagnostics:@{@"recovered":@1}];state=[NSDictionary dictionaryWithContentsOfFile:currentPath];
            assert([state[@"recovered"] intValue]==1&&!state[@"failed"]);
        }
    }
}
static void batchTerminalWriteFaultCases(){
    for(unsigned operation=0;operation<3;++operation){
        for(unsigned fault=1;fault<=3;++fault){
            @autoreleasepool {
                batchPrepare(false);BatchFixtureManager *manager=[BatchFixtureManager new];FixtureManager *base=managerFor(0);
                manager.before=base.before;manager.after=base.after;manager.terminalSuccess=YES;
                BatchCurrentLifecycle *value=[BatchCurrentLifecycle new];[value setValue:manager forKey:@"manager"];
                auto result=std::make_shared<Reply>();bool caught=false;
                @try {try {
                    if(operation==0){
                        [value refreshForTrigger:@"write-fault" force:YES completion:completionFor(result)];
                        await([&]{return manager.requests==1;});batchWriteFault=fault;manager.reply(YES,@"terminal");
                    }else {
                        manager.writeFaultOnReply=fault;
                        if(operation==1)[value activateLicenseKey:@"fixture" intent:@"fixture" completion:completionFor(result)];
                        else [value deactivateWithCompletion:completionFor(result)];
                    }
                }catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"DiagnosticsBatch"]);caught=true;}
                batchWriteFault=0;
                await([&]{return result->calls.load()==1;});[value drainDecisions];
                assert(result->success&&!value.requestInFlight&&!value.diagnosticsBatchActive&&!value.diagnosticsBatchState);
                assert(!caught);
                assert(manager.requests==(operation==0?1U:0U)&&manager.terminalCalls==(operation==0?0U:1U));
                assert(value.reloads==1&&value.reasons.count==1);
                // Failed diagnostics are discarded, never a reason to replay the
                // successful manager call or the accepted UI/reload effects.
                [value updateDiagnostics:@{@"after_fault":@1}];
                NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:currentPath];assert([state[@"after_fault"] intValue]==1);
                manager.reply=nil;
            }
        }
    }
}
static void batchConcurrentCases(){
    batchPrepare(false);BatchCurrentLifecycle *value=[BatchCurrentLifecycle new];
    dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
    std::atomic<bool> started{false},finished{false};
    const unsigned reads=batchReads(false),writes=batchWrites(false);
    std::thread first([value,entered,release]{@autoreleasepool {
        [value performDiagnosticsBatch:^{[value updateDiagnostics:@{@"first":@1}];dispatch_semaphore_signal(entered);waitSemaphore(release);[value updateDiagnostics:@{@"second":@2}];}];
    }});
    waitSemaphore(entered);
    std::thread second([value,&started,&finished]{@autoreleasepool {started=true;[value updateDiagnostics:@{@"other":@3}];finished=true;}});
    await([&]{return started.load();});assert(!finished.load()&&batchWrites(false)==writes);
    dispatch_semaphore_signal(release);first.join();second.join();
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:currentPath];
    assert([state[@"first"] intValue]==1&&[state[@"second"] intValue]==2&&[state[@"other"] intValue]==3);
    assert(batchReads(false)==reads+2&&batchWrites(false)==writes+2&&!value.diagnosticsBatchActive&&!value.diagnosticsBatchState);
}
static void diagnosticsBatchCases(){
    puts("License diagnostics batches: complete actual/preceding terminal flows, real plist reads/writes and synchronous owner cleanup");
    batchBasicCases();batchSnapshotCases();batchFaultCases();batchTerminalWriteFaultCases();batchConcurrentCases();
    puts("License diagnostics batch passed: 48 complete refresh/activation/deactivation success/failure comparisons, four-to-two success and three-to-two failure plist reads/writes, nested/history/visible state, fresh external replacements, isolated throwing mutations, read/write NO/NS/C++ recovery, nine committed-effect write failures without replay and concurrent writer serialization. HTTP, signed persistence, UI and reload effects are controlled; device performance remains unqualified.");
}
