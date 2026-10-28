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
const [actual,frozen,commitFrozen]=await Promise.all(['shared/TLinkRunHistory.mm','test/fixtures/run-history-legacy-v1.inc','test/fixtures/run-history-commit-legacy-v1.inc'].map(read));
const beforeCommit=commitFrozen.slice(commitFrozen.indexOf('\n')+1);
const invalidation=between(actual,'    // A required mutation write','    if (sTLinkRunHistoryPersistenceFailures');
assert.match(invalidation,/operation isEqualToString:@"begin"[\s\S]*operation isEqualToString:@"finish"/);
assert.match(invalidation,/stage isEqualToString:@"evidence"[\s\S]*stage isEqualToString:@"record"[\s\S]*stage isEqualToString:@"index"[\s\S]*sTLinkRunHistoryRecovered = NO/);
const beforeRearm=actual.replace(invalidation,'');
assert.equal(createHash('sha256').update(beforeRearm.trim()).digest('hex'),'ad9d6216ba7fc2f4167c72755309a802142bac10533124672a0639a3614b6a5b','reversing only required-write invalidation must reproduce complete C03i baseline 7f212b05');
const recovery=between(actual,'// Repair only committed','static NSArray<NSDictionary *> *TLinkRunHistoryTrim');
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
console.log('Run history source passed: required-write failure re-enables retained-metadata recovery, fail-closed reads, checked commit/cleanup, bounded diagnostics, finally and frozen record/status fields.');
if(process.platform!=='darwin'){
    console.log('macOS actual/frozen history Foundation/POSIX/redaction/lock integration included in CI; not run on this host.');
}else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-run-history-'));
    const adapt=text=>text.replace(/^#(?:import|include).*\n/gm,'')
        .replace('return @"/var/mobile/Library/TLinkauto/run-history";','return fixtureRoot;')
        .replaceAll('[NSRegularExpression regularExpressionWithPattern:','[HistoryRegexFactory regularExpressionWithPattern:')
        .replace('    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];','    historyIndexReadProbe();\n    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];')
        .replace('[NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath() options:0 error:&readError]','historyReadMutationData(TLinkRunHistoryIndexPath(), &readError)')
        .replace('open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)','historyRecoveryOpen(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)')
        .replace('fstat(fd, &info)','historyRecoveryStat(fd, &info)')
        .replace('read(fd, (uint8_t *)data.mutableBytes + offset, count)','historyRecoveryRead(fd, (uint8_t *)data.mutableBytes + offset, count)')
        .replace('        NSUInteger bounded = limit == 0','        historyStatusPreparationProbe();\n        NSUInteger bounded = limit == 0')
        .replace('![data writeToFile:path atomically:YES]','!historyWriteData(data,path)')
        .replace('[[NSFileManager defaultManager] removeItemAtPath:standard error:nil]','historyRemoveArtifact(standard)');
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        await Promise.all([writeFile(join(temp,'HistoryUnderTest.inc'),adapt(actual)),writeFile(join(temp,'HistoryLegacy.inc'),adapt(old))]);
        const binary=join(temp,'run-history-runtime');
        run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/run-history-runtime-test.mm'),'-o',binary]);
        run(binary,[temp]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-run-history-'));await rm(temp,{recursive:true,force:true});}
}
