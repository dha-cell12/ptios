import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const between=(text,a,b)=>{const x=text.indexOf(a),y=text.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return text.slice(x,y);};
const [source,frozen]=await Promise.all(['shared/TLinkRunHistory.mm','test/fixtures/run-history-legacy-v1.inc'].map(read));
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
console.log('Run history preparation source passed: exact redaction, pre-flock error/tail work, snapshot read/finally release before formatting, and otherwise frozen persistence/prune/events/status fields.');
if(process.platform!=='darwin'){
    console.log('macOS actual/frozen history Foundation/POSIX/redaction/lock integration included in CI; not run on this host.');
}else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-run-history-'));
    const adapt=text=>text.replace(/^#(?:import|include).*\n/gm,'').replace('return @"/var/mobile/Library/TLinkauto/run-history";','return fixtureRoot;').replaceAll('[NSRegularExpression regularExpressionWithPattern:','[HistoryRegexFactory regularExpressionWithPattern:').replace('    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];','    historyIndexReadProbe();\n    NSData *data = [NSData dataWithContentsOfFile:TLinkRunHistoryIndexPath()];').replace('        NSUInteger bounded = limit == 0','        historyStatusPreparationProbe();\n        NSUInteger bounded = limit == 0');
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        await Promise.all([writeFile(join(temp,'HistoryUnderTest.inc'),adapt(source)),writeFile(join(temp,'HistoryLegacy.inc'),adapt(old))]);
        const binary=join(temp,'run-history-runtime');
        run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/run-history-runtime-test.mm'),'-o',binary]);
        run(binary,[temp]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-run-history-'));await rm(temp,{recursive:true,force:true});}
}
