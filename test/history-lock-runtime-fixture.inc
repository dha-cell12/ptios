// C03v: real direct-directory and stable-inode admission around the actual flock.
static void historyLockRejected(unsigned operation){
    const size_t reads=historyIndexReads,opens=historyRecoveryOpens,markers=historyMarkerChanges,permissions=historyLockPermissions;
    const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;
    const BOOL ready=Current::sTLinkRunHistoryRecovered;
    NSDictionary *reply=operation==2?Current::TLinkRunHistorySnapshot(0):historyMutation(operation==0);
    if(operation==2)assert([reply[@"error"] isEqualToString:@"history_snapshot_lock_failed"]);
    else assert(!reply.count);
    NSDictionary *last=Current::sTLinkRunHistoryLastPersistenceFailure;
    assert([last[@"stage"] isEqualToString:@"lock"]&&[last[@"code"] isEqualToString:@"history_lock_failed"]);
    assert(historyIndexReads==reads&&historyRecoveryOpens==opens&&historyMarkerChanges==markers&&historyLockPermissions==permissions);
    assert(historyWriteAttempts.count==writes&&historyEvents.count==events&&Current::sTLinkRunHistoryRecovered==ready);
    assert(historyLocks.empty()&&historyLockFds.empty()&&historyIndexFds.empty()&&historyRecoveryFds.empty());
    assert(![historyPermissionPaths containsObject:[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"]]);
}
static void historyValidatedLockCases(){
    fputs("History admission Foundation: real directories, lock descriptor and post-flock inode checks\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    NSMutableArray *savedPermissions=historyPermissionPaths;historyPermissionPaths=[NSMutableArray array];
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"validated-history-lock"];
    NSString *root=Current::fixtureRoot,*lock=[root stringByAppendingPathComponent:@"history.lock"],*index=[root stringByAppendingPathComponent:@"index.json"];
    NSFileManager *fm=[NSFileManager defaultManager];
    NSDictionary *empty=Current::TLinkRunHistorySnapshot(0);assert([empty[@"state"] isEqualToString:@"implemented"]);
    NSData *healthy=[@"{\"schema\":\"run_history_v1\",\"runs\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([healthy writeToFile:index atomically:YES]);
    struct stat original;assert(::lstat(lock.fileSystemRepresentation,&original)==0);
    for(unsigned n=0;n<128;++n){
        const size_t permissions=historyLockPermissions;int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0);
        struct stat opened,current;assert(::fstat(fd,&opened)==0&&::lstat(lock.fileSystemRepresentation,&current)==0);
        assert(opened.st_ino==original.st_ino&&opened.st_dev==original.st_dev&&current.st_ino==opened.st_ino);
        const size_t repairs=((current.st_mode&07777)!=0640?1:0)+(current.st_uid!=501||current.st_gid!=501?1:0);
        assert(historyLockPermissions==permissions+repairs);Current::TLinkRunHistoryReleaseFileLock(fd);
    }
    for(unsigned op=0;op<3;++op){historyLockOpenFault=true;historyLockRejected(op);historyLockOpenFault=false;}
    for(unsigned op=0;op<3;++op){historyLockStatFault=true;historyLockRejected(op);historyLockStatFault=false;}
    assert([healthy isEqual:[NSData dataWithContentsOfFile:index]]);
    // Lock special types/hardlinks must be refused before descriptor permissions or index IO.
    NSString *backup=[lock stringByAppendingString:@".saved"],*outside=[historyTestRoot stringByAppendingPathComponent:@"history-lock-target"];
    NSData *sentinel=[@"outside bytes" dataUsingEncoding:NSUTF8StringEncoding];assert([sentinel writeToFile:outside atomically:YES]);
    struct stat outsideInfo;assert(::stat(outside.fileSystemRepresentation,&outsideInfo)==0);
    for(unsigned kind=0;kind<5;++kind){
        assert(::rename(lock.fileSystemRepresentation,backup.fileSystemRepresentation)==0);
        if(kind==0)assert(::symlink(outside.fileSystemRepresentation,lock.fileSystemRepresentation)==0);
        if(kind==1)assert(::symlink([outside stringByAppendingString:@".missing"].fileSystemRepresentation,lock.fileSystemRepresentation)==0);
        if(kind==2)assert(::mkfifo(lock.fileSystemRepresentation,0600)==0);
        if(kind==3)assert([fm createDirectoryAtPath:lock withIntermediateDirectories:NO attributes:nil error:nil]);
        if(kind==4)assert(::link(backup.fileSystemRepresentation,lock.fileSystemRepresentation)==0);
        for(unsigned op=0;op<3;++op)historyLockRejected(op);
        assert([healthy isEqual:[NSData dataWithContentsOfFile:index]]&&[sentinel isEqual:[NSData dataWithContentsOfFile:outside]]);
        struct stat current;assert(::stat(outside.fileSystemRepresentation,&current)==0&&current.st_mode==outsideInfo.st_mode);
        assert([fm removeItemAtPath:lock error:nil]&&::rename(backup.fileSystemRepresentation,lock.fileSystemRepresentation)==0);
    }
    // Preflight the whole direct directory set before any directory permission call.
    NSString *target=[historyTestRoot stringByAppendingPathComponent:@"history-directory-target"];
    assert([fm createDirectoryAtPath:target withIntermediateDirectories:NO attributes:nil error:nil]);
    NSString *child=[target stringByAppendingPathComponent:@"untouched"];
    assert([sentinel writeToFile:child atomically:YES]);struct stat targetInfo;assert(::stat(target.fileSystemRepresentation,&targetInfo)==0);
    NSArray *directories=@[root,Current::TLinkRunHistoryRunsPath(),Current::TLinkRunHistoryEvidencePath()];
    for(NSString *path in directories)for(unsigned kind=0;kind<3;++kind){
        NSString *saved=[path stringByAppendingString:@".saved"];assert(::rename(path.fileSystemRepresentation,saved.fileSystemRepresentation)==0);
        if(kind==0)assert([sentinel writeToFile:path atomically:YES]);
        if(kind==1)assert(::symlink(target.fileSystemRepresentation,path.fileSystemRepresentation)==0);
        if(kind==2)assert(::mkfifo(path.fileSystemRepresentation,0600)==0);
        const NSUInteger permissions=historyPermissionPaths.count;
        for(unsigned op=0;op<3;++op)historyLockRejected(op);
        assert(historyPermissionPaths.count==permissions&&[sentinel isEqual:[NSData dataWithContentsOfFile:child]]);
        struct stat current;assert(::stat(target.fileSystemRepresentation,&current)==0&&current.st_mode==targetInfo.st_mode);
        assert([fm removeItemAtPath:path error:nil]&&::rename(saved.fileSystemRepresentation,path.fileSystemRepresentation)==0);
    }
    // Mutate real filesystem state after flock returns, before pathname/directory revalidation.
    for(unsigned kind=0;kind<6;++kind)for(unsigned op=0;op<3;++op){
        NSString *directory=kind==3?root:(kind==4?Current::TLinkRunHistoryRunsPath():Current::TLinkRunHistoryEvidencePath());
        NSString *savedDirectory=[directory stringByAppendingString:@".after-lock"],*alias=[root stringByAppendingPathComponent:@"lock-alias"];
        historyAfterLock=[kind,lock,backup,directory,savedDirectory,alias]{
            if(kind<2){
                assert(::rename(lock.fileSystemRepresentation,backup.fileSystemRepresentation)==0);
                if(kind==0){int fd=::open(lock.fileSystemRepresentation,O_CREAT|O_RDWR|O_EXCL,0600);assert(fd>=0&&::close(fd)==0);}
            }else if(kind==2)assert(::link(lock.fileSystemRepresentation,alias.fileSystemRepresentation)==0);
            else assert(::rename(directory.fileSystemRepresentation,savedDirectory.fileSystemRepresentation)==0&&::symlink(savedDirectory.fileSystemRepresentation,directory.fileSystemRepresentation)==0);
        };
        historyLockRejected(op);historyAfterLock={};
        if(kind<2){if(kind==0)assert(::unlink(lock.fileSystemRepresentation)==0);assert(::rename(backup.fileSystemRepresentation,lock.fileSystemRepresentation)==0);}
        else if(kind==2)assert(::unlink(alias.fileSystemRepresentation)==0);
        else assert(::unlink(directory.fileSystemRepresentation)==0&&::rename(savedDirectory.fileSystemRepresentation,directory.fileSystemRepresentation)==0);
        assert([healthy isEqual:[NSData dataWithContentsOfFile:index]]&&historyChildCanLock(lock));
    }
    // Existing missing-directory/bootstrap and logical marker recovery still work.
    assert([fm removeItemAtPath:Current::TLinkRunHistoryEvidencePath() error:nil]);
    assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    assert(historyMutation(true).count&&historyPendingSize()==0&&historyLocks.empty()&&historyLockFds.empty());
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;historyPermissionPaths=savedPermissions;
    puts("History admission passed: 128 stable-inode lifecycles, open/stat errors, lock symlink/dangling/FIFO/directory/hardlink refusal, all direct-directory types, 18 real post-flock path/link/parent replacements, no early permissions/index IO, no retained FDs, restoration/bootstrap and normal ACK. Arbitrary filesystem races/device qualification remain separate.");
}
