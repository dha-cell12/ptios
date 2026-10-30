import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const between=(text,a,b)=>{const x=text.indexOf(a),y=text.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return text.slice(x,y);};
const [permissionCurrent,frozen,commitFrozen]=await Promise.all(['shared/TLinkRunHistory.mm','test/fixtures/run-history-legacy-v1.inc','test/fixtures/run-history-commit-legacy-v1.inc'].map(read));
const permissionBlock=between(permissionCurrent,'static void TLinkRunHistoryEnsureDirectories','static void TLinkRunHistoryReleaseFileLock');
assert.match(permissionBlock,/struct stat directoryInfo\[3\][\s\S]*struct stat &info = directoryInfo\[index\+\+\]/);
assert.match(permissionBlock,/if \(\(info.st_mode & 07777\) != 0750\) chmod/);
assert.match(permissionBlock,/if \(info.st_uid != 501 \|\| info.st_gid != 501\) lchown/);
assert.match(permissionBlock,/if \(\(current.st_mode & 07777\) != 0640\) fchmod/);
assert.match(permissionBlock,/if \(current.st_uid != 501 \|\| current.st_gid != 501\) fchown/);
const consoleCurrent=permissionCurrent.replace('    struct stat directoryInfo[3];\n    NSUInteger index = 0;\n','')
    .replace('struct stat &info = directoryInfo[index++];','struct stat info;')
    .replace('    index = 0;\n','').replace('        const struct stat &info = directoryInfo[index++];\n','')
    .replace('if ((info.st_mode & 07777) != 0750) chmod','chmod')
    .replace('if (info.st_uid != 501 || info.st_gid != 501) lchown','lchown')
    .replace('if ((current.st_mode & 07777) != 0640) fchmod','fchmod')
    .replace('if (current.st_uid != 501 || current.st_gid != 501) fchown','fchown');
assert.equal(createHash('sha256').update(consoleCurrent.trim()).digest('hex'),'b9aaf589f7a7748775b88df8f81f4d6c96eb25b005e38203ff5913560fe662f3','reversing only metadata permission predicates reproduces complete user-passed C03x source at 0b7887e2');
const consoleTail=between(consoleCurrent,'static NSArray<NSString *> *TLinkRunHistoryTailFromConsoleFile','static BOOL TLinkRunHistoryRemoveArtifact');
const oldConsoleTail=between(frozen,'static NSArray<NSString *> *TLinkRunHistoryTailFromConsoleFile','static void TLinkRunHistoryRemoveArtifact');
assert.match(consoleTail,/O_RDONLY \| O_NOFOLLOW \| O_NONBLOCK/);
assert.match(consoleTail,/fstat\(fd, &consoleInfo\)[\s\S]*S_ISREG\(consoleInfo.st_mode\)/);
assert.match(consoleTail,/consoleInfo.st_size - \(off_t\)kTLinkFailureConsoleLogMaxBytes/);
assert.match(consoleTail,/dataWithLength:\(NSUInteger\)\(consoleInfo.st_size - start\)/);
assert.match(consoleTail,/MIN\(data.length - offset, \(NSUInteger\)65536\)/);
assert.match(consoleTail,/pread\(fd,[\s\S]*start \+ \(off_t\)offset\)[\s\S]*errno == EINTR[\s\S]*if \(got <= 0\) return @\[\]/);
assert.match(consoleTail,/@finally \{\n        close\(fd\)/);
assert.doesNotMatch(consoleTail,/attributesOfItemAtPath|NSFileHandle|readDataToEndOfFile/);
const sharedCurrent=consoleCurrent.replace(consoleTail,oldConsoleTail);
assert.equal(createHash('sha256').update(sharedCurrent.trim()).digest('hex'),'6534189312096e6ebd45383b63b0a57b7c90efa5787eb2b3387e52adfe102727','reversing only descriptor-bounded console tail reproduces complete user-passed C03w source at e6b1580a');
const sharedSnapshot=sharedCurrent.slice(sharedCurrent.indexOf('NSDictionary *TLinkRunHistorySnapshot('));
assert.match(sharedCurrent,/AcquireFileLock\(BOOL shared = NO\)/);
assert.match(sharedCurrent,/flock\(fd, shared \? LOCK_SH : LOCK_EX\)/);
assert.match(sharedSnapshot,/int lockFd = TLinkRunHistoryAcquireFileLock\(YES\)/);
assert.equal((sharedCurrent.match(/TLinkRunHistoryAcquireFileLock\(YES\)/g)||[]).length,1,'only snapshot requests a shared lock');
const admittedCurrent=sharedCurrent.replace('AcquireFileLock(BOOL shared = NO)','AcquireFileLock(void)')
    .replace('flock(fd, shared ? LOCK_SH : LOCK_EX)','flock(fd, LOCK_EX)')
    .replace('int lockFd = TLinkRunHistoryAcquireFileLock(YES);','int lockFd = TLinkRunHistoryAcquireFileLock();');
assert.equal(createHash('sha256').update(admittedCurrent.trim()).digest('hex'),'c5be9dddc9420019a767030fe68a5374ab13bdd6f2b7fa362860f1608dd30410','reversing only snapshot shared lock selection reproduces complete user-passed C03v source at 6be7edb0');
const [historyRuntime,indexFixture]=await Promise.all(['test/run-history-runtime-test.mm','test/history-index-runtime-fixture.inc'].map(read));
assert.match(historyRuntime,/TLinkRunHistoryFinish\(@"validation-finish",@"failed"/);
assert.ok(indexFixture.includes('NSArray *expectedWrites=beginning?@[@"record"]:@[@"evidence",@"record"];'),'oversized-index oracle must retain the failed-finish evidence write');
assert.match(indexFixture,/historyWriteAttempts isEqualToArray:expectedWrites/);
const directoryLock=between(admittedCurrent,'// Validate direct directories','static void TLinkRunHistoryReleaseFileLock');
assert.match(directoryLock,/lstat\(path.fileSystemRepresentation, &info\)[\s\S]*S_ISDIR\(info.st_mode\)/);
assert.match(directoryLock,/if \(errno != ENOENT\) return/);
assert.match(directoryLock,/fstat\(fd, &opened\)[\s\S]*S_ISREG\(opened.st_mode\)[\s\S]*opened.st_nlink != 1/);
assert.match(directoryLock,/current.st_dev != opened.st_dev \|\| current.st_ino != opened.st_ino/);
assert.match(directoryLock,/flock\(fd, LOCK_UN\);\n        close\(fd\);/);
assert.match(directoryLock,/fchmod\(fd, 0640\);\n    fchown\(fd, 501, 501\);/);
assert.ok(directoryLock.indexOf('fchmod(fd')>directoryLock.indexOf('current.st_ino'));
assert.ok(directoryLock.indexOf('current.st_ino')>directoryLock.indexOf('flock(fd, LOCK_EX)'));
const oldDirectoryLock="static void TLinkRunHistoryEnsureDirectories(void)\n{\n    NSDictionary *attributes = @{NSFilePosixPermissions: @0750};\n    NSFileManager *fm = [NSFileManager defaultManager];\n    for (NSString *path in @[TLinkRunHistoryRootPath(), TLinkRunHistoryRunsPath(), TLinkRunHistoryEvidencePath()]) {\n        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:nil];\n        chmod(path.fileSystemRepresentation, 0750);\n        lchown(path.fileSystemRepresentation, 501, 501);\n    }\n}\n\nstatic int TLinkRunHistoryAcquireFileLock(void)\n{\n    NSString *path = TLinkRunHistoryFileLockPath();\n    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640);\n    if (fd < 0) return -1;\n    chmod(path.fileSystemRepresentation, 0640);\n    lchown(path.fileSystemRepresentation, 501, 501);\n    if (flock(fd, LOCK_EX) != 0) {\n        close(fd);\n        return -1;\n    }\n    return fd;\n}\n\n";
const boundedCurrent=admittedCurrent.replace(directoryLock,oldDirectoryLock);
assert.equal(createHash('sha256').update(boundedCurrent.trim()).digest('hex'),'efd86cd685eb6b9179fc4f5c949e6836bd9cb070917aa3b5b58d183fc9db1f66','reversing only direct directory/lock inode admission reproduces complete user-passed C03u source at d4f8fa95');
const boundedIndexRead=between(boundedCurrent,'// Bounded index reads:','// All persisted reads distinguish');
assert.match(boundedCurrent,/kTLinkRunHistoryIndexMaxBytes = 32 \* 1024 \* 1024/);
assert.match(boundedIndexRead,/O_RDONLY \| O_NOFOLLOW \| O_NONBLOCK/);
assert.match(boundedIndexRead,/fstat\(fd, &indexInfo\)[\s\S]*S_ISREG\(indexInfo.st_mode\)/);
assert.ok(boundedIndexRead.indexOf('indexInfo.st_size > kTLinkRunHistoryIndexMaxBytes')<boundedIndexRead.indexOf('dataWithLength:'));
assert.match(boundedIndexRead,/MIN\(indexData.length - offset, \(NSUInteger\)65536\)/);
assert.match(boundedIndexRead,/read\(fd, &extra, 1\)[\s\S]*@finally \{ close\(fd\); \}/);
assert.match(boundedIndexRead,/errno == ENOENT[\s\S]*errno == EINTR/);
assert.ok(boundedCurrent.includes('([path isEqualToString:TLinkRunHistoryIndexPath()] && data.length > kTLinkRunHistoryIndexMaxBytes) ||\n        ![data writeToFile:path atomically:YES]'));
const readPrefix=between(boundedCurrent,'    BOOL missing = NO;','    id object =');
const oldReadPrefix="    NSError *readError = nil;\n    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath() options:0 error:&readError];\n    if (!data) {\n        if ([readError.domain isEqualToString:NSCocoaErrorDomain] &&\n            (readError.code == NSFileReadNoSuchFileError || readError.code == NSFileNoSuchFileError)) {\n            return [NSMutableArray array];\n        }\n        TLinkRunHistoryPersistenceFailure(operation, @\"read\", @\"read_failed\");\n        return nil;\n    }\n";
const current=boundedCurrent.replace('static const NSUInteger kTLinkRunHistoryIndexMaxBytes = 32 * 1024 * 1024;\n','')
    .replace(boundedIndexRead,'').replace(readPrefix,oldReadPrefix)
    .replace('if (!data || ([path isEqualToString:TLinkRunHistoryIndexPath()] && data.length > kTLinkRunHistoryIndexMaxBytes) ||\n        ![data writeToFile:path atomically:YES])','if (!data || ![data writeToFile:path atomically:YES])')
    .replace('? @"history_snapshot_invalid_index" :\n                ([sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"index_too_large"]\n                    ? @"history_snapshot_too_large" : @"history_snapshot_read_failed"))','? @"history_snapshot_invalid_index" : @"history_snapshot_read_failed")');
assert.equal(createHash('sha256').update(current.trim()).digest('hex'),'0a26786c6524c793502bf585c3c87583fe34676e446a9579439395500f76312e','reversing only bounded index IO/write cap/too-large status reproduces complete user-passed history at 232ebbe7');
const snapshotFrozenText=await read('test/fixtures/run-history-snapshot-legacy-v1.inc');
const snapshotFrozen=snapshotFrozenText.slice(snapshotFrozenText.indexOf('\n')+1);
const snapshotCurrent=current.slice(current.indexOf('NSDictionary *TLinkRunHistorySnapshot('));
const snapshotFailure=between(current,'// Failed status counts/runs','NSDictionary *TLinkRunHistorySnapshot(');
assert.match(snapshotCurrent,/lockFd < 0[\s\S]*history_snapshot_lock_failed[\s\S]*TLinkRunHistoryReadCheckedIndex\(@"snapshot"\)/);
assert.match(snapshotCurrent,/@finally[\s\S]*TLinkRunHistoryReleaseFileLock\(lockFd\)/);
assert.match(snapshotCurrent,/history_snapshot_invalid_index[\s\S]*history_snapshot_read_failed[\s\S]*stage = @"format"/);
assert.match(snapshotCurrent,/catch \(\.\.\.\)[\s\S]*@catch[\s\S]*history_snapshot_exception/);
assert.doesNotMatch(snapshotCurrent+snapshotFailure,/TLinkRunHistory(?:Write|Recover|Prune|SetPending)|EventChannelPublish/);
assert.match(snapshotFailure,/@"state": @"error"[\s\S]*@"error": code[\s\S]*@"runs": @\[\]/);
const statusFields=between(snapshotCurrent,'            NSUInteger bounded =','            return snapshot;').split('\n').map(line=>line.startsWith('    ')?line.slice(4):line).join('\n');
assert.equal(statusFields,between(snapshotFrozen,'        NSUInteger bounded =','        return snapshot;'),'successful snapshot formatting/fields stay frozen');
const oldStatusReader="static NSMutableArray<NSDictionary *> *TLinkRunHistoryReadIndex(void)\n{\n    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];\n    if (data.length == 0) return [NSMutableArray array];\n    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];\n    NSArray *records = [object isKindOfClass:[NSDictionary class]] ? object[@\"runs\"] : nil;\n    return [records isKindOfClass:[NSArray class]] ? [records mutableCopy] : [NSMutableArray array];\n}\n\n";
const actual=current.replace(snapshotFailure,'').replace(snapshotCurrent,snapshotFrozen)
    .replaceAll('TLinkRunHistoryReadCheckedIndex','TLinkRunHistoryReadIndexForMutation')
    .replace('// All persisted reads distinguish a first run from unreadable or damaged history.\n// Read-only status never repairs metadata or rebuilds an index from artifacts.','// Mutations must distinguish a first run from unreadable or damaged history.\n// Keep the permissive status reader separate; never rebuild an index from artifacts.')
    .replace('static BOOL TLinkRunHistoryWriteJSON',oldStatusReader+'static BOOL TLinkRunHistoryWriteJSON');
assert.equal(createHash('sha256').update(actual.trim()).digest('hex'),'34b6f42b08b699ff32aa49b6dd9120db2f546e6ea4c00907589b3d6769701e58','reversing only checked snapshot reads/errors and common reader naming reproduces complete user-passed history at c20c70d9');
const beforeCommit=commitFrozen.slice(commitFrozen.indexOf('\n')+1);
const encoder=between(actual,'static BOOL TLinkRunHistoryWriteJSON','static BOOL TLinkRunHistoryWriteIndex');
assert.ok(encoder.includes('NSJSONWritingOptions options = NSJSONWritingPrettyPrinted'));
assert.ok(encoder.includes('dataWithJSONObject:object options:options error:nil'));
assert.match(between(actual,'static BOOL TLinkRunHistoryWriteIndex','static NSArray<NSRegularExpression *>'), /\}, TLinkRunHistoryIndexPath\(\), 0\);/);
const beforeCompact=actual
    .replace('static BOOL TLinkRunHistoryWriteJSON(id object, NSString *path, NSJSONWritingOptions options = NSJSONWritingPrettyPrinted)','static BOOL TLinkRunHistoryWriteJSON(id object, NSString *path)')
    .replace('dataWithJSONObject:object options:options error:nil','dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil')
    .replace('}, TLinkRunHistoryIndexPath(), 0);','}, TLinkRunHistoryIndexPath());');
assert.notEqual(actual,beforeCompact);
assert.equal(createHash('sha256').update(beforeCompact.trim()).digest('hex'),'76ef6fa6e9d4fa9f1a8ac983a6ed69a58f56c425ae2e7c2506b01bb1232355a3','reversing only compact index serialization must reproduce complete user-passed C03l working source');
const ownedCleanup=between(beforeCompact,'// Retirement owns only exact per-ID leaves','NSDictionary *TLinkRunHistoryBegin');
assert.match(ownedCleanup,/retained containsObject:path/);
assert.match(ownedCleanup,/path isEqualToString:expected/);
assert.match(ownedCleanup,/lstat\(directory.fileSystemRepresentation, &info\)[\s\S]*S_ISDIR/);
assert.match(ownedCleanup,/PersistenceFailure\(@"prune", @"artifacts", @"remove_failed"\)/);
assert.doesNotMatch(ownedCleanup,/WriteJSON|WriteIndex|EventChannelPublish|removeItemAtPath/);
const removal=between(beforeCompact,'static BOOL TLinkRunHistoryRemoveArtifact','static uint64_t sTLinkRunHistoryPersistenceFailures');
assert.match(removal,/unlink\(path.fileSystemRepresentation\)[\s\S]*errno == EINTR[\s\S]*errno == ENOENT/);
const oldRemoval=between(beforeCommit,'static void TLinkRunHistoryRemoveArtifact','static void TLinkRunHistoryPrune');
const oldCleanup=`static void TLinkRunHistoryPrune(NSArray<NSDictionary *> *retired)
{
    for (NSDictionary *oldest in retired) {
        @try { try {
            TLinkRunHistoryRemoveArtifact(oldest[@"record_path"]);
            NSDictionary *evidence = [oldest[@"failure_evidence"] isKindOfClass:[NSDictionary class]] ? oldest[@"failure_evidence"] : @{};
            TLinkRunHistoryRemoveArtifact(evidence[@"metadata_path"]);
            TLinkRunHistoryRemoveArtifact(evidence[@"screenshot_path"]);
        } catch (...) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); } }
        @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); }
    }
}

`;
const beforeCleanup=beforeCompact.replace(removal,oldRemoval).replace(ownedCleanup,oldCleanup).replaceAll('TLinkRunHistoryPrune(retired, runs);','TLinkRunHistoryPrune(retired);');
assert.equal(createHash('sha256').update(beforeCleanup.trim()).digest('hex'),'b9f1354a2fa793ae8bf56f68907621c3309c8973941fa8d33ec3da55e67b5129','reversing only checked per-ID retirement must reproduce the complete user-passed C03k working baseline');
const marker=between(beforeCleanup,'// The held lock inode','static NSArray<NSDictionary *> *TLinkRunHistoryTrim');
assert.ok(beforeCleanup.includes('O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640'));
assert.match(marker,/ftruncate\(lockFd, pending \? 1 : 0\)[\s\S]*errno == EINTR/);
assert.match(marker,/fstat\(lockFd, &marker\)/);
assert.match(marker,/S_ISREG\(marker.st_mode\)[\s\S]*marker.st_nlink != 1[\s\S]*marker.st_size > 1/);
assert.match(marker,/marker.st_size == 1\) sTLinkRunHistoryRecovered = NO/);
assert.match(marker,/!sTLinkRunHistoryRecovered[\s\S]*SetPending\(lockFd, YES[\s\S]*return TLinkRunHistoryRecover\(runs, operation\)/);
assert.doesNotMatch(marker,/WriteJSON|WriteIndex|EventChannelPublish|unlink\(|removeItem/);
let beforeMarker=beforeCleanup.replace(marker,'').replace('O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640','O_CREAT | O_RDWR, 0640');
for(const operation of ['begin','finish']){
    const section=between(beforeCleanup,operation==='begin'?'NSDictionary *TLinkRunHistoryBegin':'NSDictionary *TLinkRunHistoryFinish',operation==='begin'?'NSDictionary *TLinkRunHistoryFinish':'NSDictionary *TLinkRunHistorySnapshot');
    assert.ok(section.indexOf(`TLinkRunHistorySetPending(lockFd, YES, @"${operation}"`)<section.indexOf('TLinkRunHistoryWriteJSON('),'intent precedes artifact writes');
    assert.ok(section.indexOf(`TLinkRunHistorySetPending(lockFd, NO, @"${operation}"`)>section.indexOf('if (!TLinkRunHistoryWriteIndex(runs))'),'clear only after positive index acknowledgment');
    beforeMarker=beforeMarker.replace(`TLinkRunHistoryPrepareRecovery(runs, @"${operation}", lockFd)`,`TLinkRunHistoryRecover(runs, @"${operation}")`);
    const intent=`            stage = @"intent";\n            if (!TLinkRunHistorySetPending(lockFd, YES, @"${operation}", stage)) return @{};\n`;
    const clear=`            stage = @"commit_marker";\n            (void)TLinkRunHistorySetPending(lockFd, NO, @"${operation}", stage);\n`;
    assert.ok(beforeMarker.includes(intent)&&beforeMarker.includes(clear));
    beforeMarker=beforeMarker.replace(intent,'').replace(clear,'');
}
assert.equal(createHash('sha256').update(beforeMarker.trim()).digest('hex'),'c6392f8e6e2b98f044a77de64c2cebe319e0d69652688f518d14682c3eb843e6','reversing only lock-inode intent coordination must reproduce complete C03j baseline 0c5de74d');
const invalidation=between(beforeCleanup,'    // A required mutation write','    if (sTLinkRunHistoryPersistenceFailures');
assert.match(invalidation,/operation isEqualToString:@"begin"[\s\S]*operation isEqualToString:@"finish"/);
assert.match(invalidation,/stage isEqualToString:@"evidence"[\s\S]*stage isEqualToString:@"record"[\s\S]*stage isEqualToString:@"index"[\s\S]*sTLinkRunHistoryRecovered = NO/);
const beforeRearm=beforeMarker.replace(invalidation,'');
assert.equal(createHash('sha256').update(beforeRearm.trim()).digest('hex'),'ad9d6216ba7fc2f4167c72755309a802142bac10533124672a0639a3614b6a5b','reversing only required-write invalidation must reproduce complete C03i baseline 7f212b05');
const recovery=between(beforeMarker,'// Repair only committed','static NSArray<NSDictionary *> *TLinkRunHistoryTrim');
assert.match(recovery,/if \(sTLinkRunHistoryRecovered\) return YES/);
assert.match(recovery,/runs.count <= kTLinkRunHistoryMaxRecords/);
assert.match(recovery,/paths containsObject:recordPath/);
assert.match(recovery,/O_RDONLY \| O_NONBLOCK \| O_NOFOLLOW/);
assert.match(recovery,/lstat\(directory.fileSystemRepresentation, &info\)[\s\S]*S_ISDIR/);
assert.match(recovery,/fstat\(fd, &info\)[\s\S]*S_ISREG/);
assert.match(recovery,/info.st_size == encoded.length[\s\S]*MIN\(data.length - offset, \(NSUInteger\)65536\)/);
assert.match(recovery,/errno == EINTR[\s\S]*@finally \{ close\(fd\); \}/);
assert.match(recovery,/if \(!TLinkRunHistoryWriteJSON\(expected, path\)\)/);
assert.match(recovery,/sTLinkRunHistoryRecovered = YES;\n    return YES;/);
assert.doesNotMatch(recovery,/WriteIndex|EventChannelPublish|RemoveArtifact|removeItem|contentsOfDirectory|unlink\(/);
let checked=beforeRearm.replace('#include <errno.h>\n','').replace('static BOOL sTLinkRunHistoryRecovered = NO;\n','').replace(recovery,'');
for(const operation of ['begin','finish']){
    const gate=`            stage = @"recovery";\n            if (!TLinkRunHistoryRecover(runs, @"${operation}")) return @{};\n`;
    assert.ok(checked.includes(gate));checked=checked.replace(gate,'');
}
assert.equal(createHash('sha256').update(checked.trim()).digest('hex'),'e9abd5a44aa4488ea68c0715e93ffbf18a57dc801c6b02813b3fb5d720ddce57','reversing only startup recovery must reproduce complete C03h baseline c8d2d085');
const mutationReader=between(checked,'// Mutations must distinguish','static NSArray<NSDictionary *> *TLinkRunHistoryTrim');
assert.match(mutationReader,/options:0 error:&readError/);
assert.match(mutationReader,/NSCocoaErrorDomain[\s\S]*NSFileReadNoSuchFileError[\s\S]*NSFileNoSuchFileError/);
assert.match(mutationReader,/schema isEqualToString:TLinkRunHistorySchemaV1/);
assert.match(mutationReader,/records isKindOfClass:\[NSArray class\]/);
assert.match(mutationReader,/record isKindOfClass:\[NSDictionary class\][\s\S]*runId isKindOfClass:\[NSString class\][\s\S]*identities containsObject:runId/);
assert.match(mutationReader,/PersistenceFailure\(operation, @"read", @"read_failed"\)/);
assert.match(mutationReader,/PersistenceFailure\(operation, @"read", @"invalid_index"\)/);
assert.doesNotMatch(mutationReader,/WriteJSON|WriteIndex|RemoveArtifact|removeItem|EventChannelPublish|contentsOfDirectory/);
const cleanup=between(checked,'static uint64_t sTLinkRunHistoryPersistenceFailures','NSDictionary *TLinkRunHistoryBegin');
assert.match(cleanup,/sTLinkRunHistoryPersistenceFailures != UINT64_MAX/);
assert.doesNotMatch(between(cleanup,'static NSArray<NSDictionary *> *TLinkRunHistoryTrim','static void TLinkRunHistoryPrune'),/RemoveArtifact|removeItem/,'trim must only change the pending index');
assert.match(cleanup,/for \(NSDictionary \*oldest in retired\)[\s\S]*RemoveArtifact\(oldest\[@"record_path"\]\)[\s\S]*RemoveArtifact\(evidence\[@"metadata_path"\]\)[\s\S]*RemoveArtifact\(evidence\[@"screenshot_path"\]\)[\s\S]*@catch/);
let source=checked.replace('#include <stdint.h>\n','').replace(cleanup,between(beforeCommit,'static void TLinkRunHistoryPrune','NSDictionary *TLinkRunHistoryBegin'));
for(const [operation,start,end] of [['begin','NSDictionary *TLinkRunHistoryBegin','NSDictionary *TLinkRunHistoryFinish'],['finish','NSDictionary *TLinkRunHistoryFinish','NSDictionary *TLinkRunHistorySnapshot']]){
    const read=`TLinkRunHistoryReadIndexForMutation(@"${operation}");\n            if (!runs) return @{};`;
    assert.ok(between(source,start,end).includes(read),'required index read must stop before evidence/record/index writes');
    source=source.replace(read,'TLinkRunHistoryReadIndex();');
    const section=between(source,start,end);
    assert.ok(section.indexOf('if (!TLinkRunHistoryWriteIndex(runs))')<section.indexOf('TLinkRunHistoryPrune(retired)'));
    assert.match(section,/@finally \{ TLinkRunHistoryReleaseFileLock\(lockFd\); \}[\s\S]*TLinkEventChannelPublish/,'release before publishing committed state');
    const wrapper=between(section,operation==='begin'?'        NSString *runId = nil;':'        NSMutableDictionary *record = nil;','        TLinkEventChannelPublish');
    let body=between(wrapper,'        @try { try {\n',`        } catch (...) { TLinkRunHistoryPersistenceFailure(@"${operation}"`).slice('        @try { try {\n'.length);
    body=body.split('\n').map(line=>line.startsWith('    ')?line.slice(4):line).join('\n');
    body=body.replace(/^        stage = @"(?:read|prepare|record|index)";\n/gm,'').replace('            stage = @"evidence";\n','');
    for(const [call,indent] of [['TLinkRunHistoryWriteJSON(record, recordPath)','        '],['TLinkRunHistoryWriteIndex(runs)','        '],...(operation==='finish'?[['TLinkRunHistoryWriteJSON(evidence, metadataPath)','            ']]:[])]){
        const guard=`${indent}if (!${call}) { TLinkRunHistoryPersistenceFailure(@"${operation}", stage, @"write_failed"); return @{}; }`;
        assert.ok(body.includes(guard),`${operation}: ${call} must fail without success/event`);body=body.replace(guard,`${indent}${call};`);
    }
    body=body.replace('        NSArray *retired = TLinkRunHistoryTrim(runs);','        TLinkRunHistoryPrune(runs);').replace('        TLinkRunHistoryPrune(retired);\n','');
    if(operation==='begin')body=body.replace('        runId = ','        NSString *runId = ').replace('        record = @{','        NSDictionary *record = @{');
    else body=body.replace('        record = index','        NSMutableDictionary *record = index');
    let restoredSection=section.replace(wrapper,body+'        TLinkRunHistoryReleaseFileLock(lockFd);\n');
    restoredSection=restoredSection.replace(`        if (lockFd < 0) { TLinkRunHistoryPersistenceFailure(@"${operation}", @"lock", @"history_lock_failed"); return @{}; }`,'        if (lockFd < 0) return @{};');
    source=source.replace(section,restoredSection);
}
const diagnostics='            @"persistence_diagnostics": @{@"scope": @"process", @"failure_count": @(sTLinkRunHistoryPersistenceFailures), @"last_failure": sTLinkRunHistoryLastPersistenceFailure ?: @{}},\n';
assert.ok(source.includes(diagnostics));source=source.replace(diagnostics,'');
assert.equal(source.trim(),beforeCommit.trim(),'only checked writes, post-index artifact cleanup, exception-safe transaction release and additive diagnostics change C03f');
const old=frozen.slice(frozen.indexOf('\n')+1);
const cache=between(source,'static NSArray<NSRegularExpression *> *TLinkRunHistoryRedactionPatterns','static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail');
const oldRedaction=between(old,'static NSString *TLinkRunHistoryRedactText','static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail');
assert.match(cache,/dispatch_once\(&onceToken[\s\S]*regularExpressionWithPattern:pattern options:0 error:nil[\s\S]*compiled = \[expressions copy\]/);
assert.equal(between(cache,'        @"(?i)','        ];').trim(),between(oldRedaction,'        @"(?i)','    ];').trim(),'keep exact redaction patterns and their order');
const finish=between(source,'NSDictionary *TLinkRunHistoryFinish','NSDictionary *TLinkRunHistorySnapshot');
const preparation=between(finish,'        // Preparation is process-serialized','        int lockFd = TLinkRunHistoryAcquireFileLock();');
const terminal='        NSString *terminalState = state.length > 0 ? state : @"finished";\n';
const failure='        BOOL failed = [terminalState isEqualToString:@"failed"] || [terminalState isEqualToString:@"license_revoked"];\n';
const errorPreparation=between(preparation,'        NSString *redactedError','        BOOL failed');
const tailPreparation='            NSArray *tail = TLinkRunHistoryBoundedLogTail(logTail);\n            if (tail.count == 0) tail = TLinkRunHistoryTailFromConsoleFile(consoleLogPath);\n';
assert.match(preparation,/TLinkRunHistoryRedactText[\s\S]*BOOL failed[\s\S]*if \(failed\)[\s\S]*TLinkRunHistoryBoundedLogTail[\s\S]*TLinkRunHistoryTailFromConsoleFile/);
assert.doesNotMatch(finish.slice(finish.indexOf('int lockFd =')),/TLinkRunHistoryRedactText\(|TLinkRunHistoryBoundedLogTail\(|TLinkRunHistoryTailFromConsoleFile\(/);
let restored=source.replace(cache,oldRedaction).replace(preparation,'');
restored=restored.replace('        record[@"schema"] = TLinkRunHistorySchemaV1;',terminal+'        record[@"schema"] = TLinkRunHistorySchemaV1;');
restored=restored.replace('        record[@"error"] = redactedError;',errorPreparation+'        record[@"error"] = redactedError;');
restored=restored.replace('        if (failed) {\n            NSString *metadataPath',failure+'        if (failed) {\n'+tailPreparation+'            NSString *metadataPath');
const snapshot=source.slice(source.indexOf('NSDictionary *TLinkRunHistorySnapshot'));
const snapshotRead=between(snapshot,'        NSMutableArray<NSDictionary *> *runs = nil;','        NSUInteger bounded =');
assert.match(snapshotRead,/@try[\s\S]*TLinkRunHistoryReadIndex\(\)[\s\S]*@finally[\s\S]*TLinkRunHistoryReleaseFileLock\(lockFd\)/);
assert.equal([...snapshot.matchAll(/TLinkRunHistoryReleaseFileLock\(lockFd\)/g)].length,1,'release exactly once, before status preparation');
assert.doesNotMatch(snapshot.slice(snapshot.indexOf('NSUInteger bounded =')),/TLinkRunHistoryReadIndex\(|TLinkRunHistoryAcquireFileLock\(|TLinkRunHistoryReleaseFileLock\(/);
restored=restored.replace(snapshotRead,'        NSMutableArray<NSDictionary *> *runs = TLinkRunHistoryReadIndex();\n');
restored=restored.replace('        return snapshot;','        TLinkRunHistoryReleaseFileLock(lockFd);\n        return snapshot;');
assert.equal(restored.trim(),old.trim(),'only cache regex construction and move evidence/status preparation outside flock; all read/write/screenshot/prune/event/status field logic stays frozen');
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.ok((await read(path)).includes('node scripts/check-run-history-safety.mjs'));
console.log('History metadata permissions source passed: reuse preflight stats, mode/owner-specific repairs and post-validation descriptor targeting; complete previous source retained.');
console.log('History console tail source passed: same-descriptor regular-file size, fixed 256-KiB window, bounded pread/EINTR/EOF and finally close; complete previous source retained.');
console.log('History shared snapshot lock source passed: snapshot-only LOCK_SH, default exclusive writers, unchanged complete admission/IO/recovery/format source.');
console.log('History directory/lock source passed: real direct directories, regular single-link descriptor, post-flock identity and descriptor permissions; complete previous source retained.');
console.log('History bounded index source passed: 32-MiB preallocation/read and encoded index cap, regular descriptor/ENOENT/chunk/EOF/finally policy and complete prior source.');
console.log('History checked snapshot source passed: no unlocked read/fallback, fixed errors, read-only recovery state, caught read/format faults and complete frozen success/mutation source.');
console.log('Run history source passed: compact index with unchanged artifact formatting and logical payloads, checked per-ID retirement and retained-reference protection, lock-inode pending marker coordinates warm owners, required-write recovery, fail-closed reads, checked commit/cleanup, diagnostics, finally and frozen record/status fields.');
if(process.platform!=='darwin'){
    console.log('macOS actual/frozen history Foundation/POSIX/redaction/lock integration included in CI; not run on this host.');
}else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-run-history-'));
    const adapt=text=>text.replace(/^#(?:import|include).*\n/gm,'')
        .replace('return @"/var/mobile/Library/TLinkauto/run-history";','return fixtureRoot;')
        .replaceAll('[NSRegularExpression regularExpressionWithPattern:','[HistoryRegexFactory regularExpressionWithPattern:')
        .replace('    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];','    historyIndexReadProbe();\n    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];')
        .replace('TLinkRunHistoryReadIndexData(&missing, &code)','historyReadBoundedData(&missing, &code, operation, TLinkRunHistoryReadIndexData)')
        .replace('open(TLinkRunHistoryIndexPath().fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)','historyIndexOpen(TLinkRunHistoryIndexPath().fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)')
        .replace('fstat(fd, &indexInfo)','historyIndexStat(fd, &indexInfo)')
        .replace('open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)','historyConsoleOpen(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)')
        .replace('fstat(fd, &consoleInfo)','historyConsoleStat(fd, &consoleInfo)')
        .replace('[NSMutableData dataWithLength:(NSUInteger)(consoleInfo.st_size - start)]','historyConsoleBuffer((NSUInteger)(consoleInfo.st_size - start))')
        .replace('pread(fd, (uint8_t *)data.mutableBytes + offset, count, start + (off_t)offset)','historyConsoleRead(fd, (uint8_t *)data.mutableBytes + offset, count, start + (off_t)offset)')
        .replace('[NSMutableData dataWithLength:(NSUInteger)indexInfo.st_size]','historyIndexBuffer((NSUInteger)indexInfo.st_size,kTLinkRunHistoryIndexMaxBytes)')
        .replace('read(fd, (uint8_t *)indexData.mutableBytes + offset, count)','historyIndexRead(fd, (uint8_t *)indexData.mutableBytes + offset, count)')
        .replace('read(fd, &extra, 1)','historyIndexRead(fd, &extra, 1)')
        .replace('[NSJSONSerialization dataWithJSONObject:object options:options error:nil]','historyEncodeJSON(object,path,options)')
        .replace('open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)','historyRecoveryOpen(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)')
        .replace('fstat(fd, &info)','historyRecoveryStat(fd, &info)')
        .replace('fstat(lockFd, &marker)','historyMarkerStat(lockFd, &marker)')
        .replace('open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640)','historyLockOpen(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640)')
        .replace('fstat(fd, &opened)','historyLockStat(fd, &opened)')
        .replaceAll('lstat(path.fileSystemRepresentation, &info)','historyPermissionStat(path.fileSystemRepresentation, &info)')
        .replace('lstat(path.fileSystemRepresentation, &current)','historyPermissionStat(path.fileSystemRepresentation, &current)')
        .replace('fchmod(fd, 0640)','historyLockFchmod(fd, 0640)')
        .replace('fchown(fd, 501, 501)','historyLockFchown(fd, 501, 501)')
        .replace('ftruncate(lockFd, pending ? 1 : 0)','historyMarkerTruncate(lockFd, pending ? 1 : 0)')
        .replace('read(fd, (uint8_t *)data.mutableBytes + offset, count)','historyRecoveryRead(fd, (uint8_t *)data.mutableBytes + offset, count)')
        .replace('        NSUInteger bounded = limit == 0','        historyStatusPreparationProbe();\n        NSUInteger bounded = limit == 0')
        .replace('![data writeToFile:path atomically:YES]','!historyWriteData(data,path)')
        .replace('[[NSFileManager defaultManager] removeItemAtPath:standard error:nil]','historyRemoveArtifact(standard)')
        .replace('unlink(path.fileSystemRepresentation)','historyUnlinkArtifact(path.fileSystemRepresentation)');
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        await Promise.all([writeFile(join(temp,'HistoryUnderTest.inc'),adapt(permissionCurrent)),writeFile(join(temp,'HistoryLegacy.inc'),adapt(old))]);
        const binary=join(temp,'run-history-runtime');
        run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/run-history-runtime-test.mm'),'-o',binary]);
        run(binary,[temp]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-run-history-'));await rm(temp,{recursive:true,force:true});}
}
