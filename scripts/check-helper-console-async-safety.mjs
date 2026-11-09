import {restoreHelperConsoleAsync,restoreHelperConsoleMetadata,helperConsoleAsyncSpecs} from './lib/helper-console-async-baseline.mjs';
import {helperConsoleSpecs,helperConsoleBeforeHook,helperConsoleBeforeWriter} from './lib/helper-console-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const source=await read(helperConsoleAsyncSpecs.file);restoreHelperConsoleAsync(source);
assert.equal((source.match(/if\(consoleOwner\)consoleOwner->close\(\);/g)||[]).length,3,'close before every synchronous terminal summary');
assert.match(source,/Completion completedLog[\s\S]*Create\(logPath,latestPath\)[\s\S]*CloseScope consoleClose\(consoleOwner,&completedLog\)/);
const coreSource=await read('pccontrol/jsruntime/TLinkJSRuntimeCore.mm'),writer=await read('shared/TLinkHelperConsoleWriter.inc');
const core=coreSource.slice(coreSource.indexOf('- (void)prepareConsoleLogFiles {'));
let expected=between(core,'- (BOOL)appendConsoleData:','- (BOOL)writeConsoleData:')+between(core,'- (BOOL)appendConsoleVectorBatch:','- (BOOL)emitConsoleSystemLog:');
expected=expected.replaceAll('const std::vector<std::shared_ptr<TLinkConsoleLogEntry>> &','const TLinkHelperConsoleState::Batch &').replaceAll('batch.size()','batch.count')
    .replace(/batch\[([^\]]+)\]->data/g,'batch.entries[$1]->line.data').replaceAll('kTLinkautoJSMaxConsoleLogBytes','kTLinkJSHelperMaxConsoleLogBytes').replaceAll('TLinkConsoleLogVectorCapacity()','TLinkHelperConsoleVectorCapacity()');
assert.equal(between(writer.slice(writer.indexOf('@implementation')),'- (BOOL)appendConsoleData:', '@end').trim(),expected.trim(),'complete shared production append/vector/group policy');
const owner=await read('shared/TLinkHelperConsoleAsync.inc');
assert.equal(owner.split('dispatch_async(queue,').length,2);assert.equal(owner.split('dispatch_sync(queue_,').length,2);
assert.match(owner,/Consumer\(\)\)return false/);assert.match(owner,/registration.commit\(\);budget_->accepted/);
assert.match(owner,/retention_->cancel\(\)/);
const metadataSource=await read('shared/TLinkHelperConsoleLog.inc');restoreHelperConsoleMetadata(metadataSource);
const metadata=metadataSource.replace('[NSDate date]','HelperDate()').replace('[line dataUsingEncoding:NSUTF8StringEncoding]','HelperEncode(line)').replace('NSLog(','HelperSystem(');
const beforeWriter=helperConsoleBeforeWriter.replaceAll('NSFileHandle *handle','HelperOwnedHandle *handle').replace('[NSFileHandle fileHandleForWritingAtPath:path]','HelperOpen(path)').replace('[line dataUsingEncoding:NSUTF8StringEncoding]','HelperEncode(line)');
const prepared=helperConsoleSpecs.writer.replaceAll('NSFileHandle *handle','HelperOwnedHandle *handle').replace('[NSFileHandle fileHandleForWritingAtPath:path]','HelperOpen(path)').replace('    NSDictionary *attrs=','    HelperObserve(data,path);\n    NSDictionary *attrs=');
const hook=(body,name)=>`static void ${name}(JSContext *ctx,id owner,NSString *runId,NSString *logPath,NSString *latestPath){__weak id weakSelf=owner;\n${body}}\n`;
const hooks=hook(helperConsoleBeforeHook.replace('[NSDate date]','HelperDate()').replace('NSLog(','HelperSystem('),'InstallBefore')+hook(helperConsoleSpecs.hook,'InstallCurrent');
const asyncHook=between(source,'        ctx[@"_tlinkautoLog"] =','        ctx[@"_tlinkautoLoadBundleText"] =');
const install=`static void InstallAsync(JSContext *ctx,id owner,std::shared_ptr<TLinkHelperConsoleAsync::Owner> consoleOwner,NSString *runId,NSString *logPath,NSString *latestPath){__weak id weakSelf=owner;\n${asyncHook}}\n`;
const measuredWriter=writer.replaceAll('[NSFileHandle fileHandleForWritingAtPath:path]','HelperAsyncOpen(path)').replaceAll('NSFileHandle *handle','HelperOwnedHandle *handle')
    .replace('::writev(','HelperAsyncVectors(').replace('[NSMutableData dataWithCapacity:total]','HelperAsyncJoined(total)').replace('return capacity;','return HelperAsyncVectorLimit(capacity);');
for(const name of ['HelperAsyncOpen(path)','HelperAsyncVectors(','HelperAsyncJoined(total)','HelperAsyncVectorLimit(capacity)'])assert.ok(measuredWriter.includes(name),name);
const measuredOwner=owner.replace('dispatch_async(queue,','HelperAsyncEnqueue(queue,').replace('dispatch_sync(queue_,','HelperAsyncBarrier(queue_,').replace('NSLog(','HelperAsyncSystem(');
console.log('Helper async console source passed: complete prior helper/metadata reversal, three pre-summary closes, scope before retention, one transactional drain job and exact production vector/group helpers.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-console-async-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    await Promise.all([['HelperConsoleUnderTest.inc',metadata],['HelperConsoleBeforeWriter.inc',beforeWriter],['HelperConsoleWriter.inc',prepared],['HelperConsoleHooks.inc',hooks],
        ['TLinkHelperConsoleWriter.inc',measuredWriter],['HelperConsoleAsyncUnderTest.inc',measuredOwner],['HelperConsoleAsyncHook.inc',install]].map(([name,text])=>writeFile(join(temp,name),text)));
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/helper-console-queue-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/helper-console-async-runtime-test.mm'),'-o',native]);run(native,[temp]);
    }else console.log('macOS actual helper async queue/vector/JSCore/drain/retention runtime included in CI; not executed here.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-console-async-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
