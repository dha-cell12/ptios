import {productionLogBatchBefore} from './lib/production-log-batch-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {productionLogSpecs,restoreProductionLog,checkProductionLogHelpers} from './lib/production-log-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
checkProductionLogHelpers();
const files={};for(const [kind,spec] of Object.entries(productionLogSpecs.files)){assert.ok(!spec.file.includes('\\'),'portable relative source path');files[kind]=await read(spec.file);restoreProductionLog(files[kind],kind);}
const oldServer=restoreProductionLog(files.server);
const api=files.header.split('\n').find(line=>line.startsWith('void POCLogf('))+'\n'+between(files.header,'// BEGIN bounded production log API.','// END bounded production log API.');
let backend=(await read('stream-app/streamd/TLinkProductionLog.inc')).replaceAll('"../../shared/','"');
backend=backend.replace('return queue;','return FixtureLogQueue(queue);').replace('dispatch_async(queue,','FixtureLogEnqueue(queue,').replace('NSLog(@"[poc-touch] %s",msg)','FixtureSystemLog(@"[poc-touch] %s",msg)')
    .replace('[df stringFromDate:[NSDate date]]','FixtureLogStamp()').replace('return limit;','return FixtureLogVectorLimit(limit);');
for(const [a,b] of [['::open(','FixtureLogOpen('],['::flock(','FixtureLogFlock('],['::fstat(','FixtureLogStat('],['::ftruncate(','FixtureLogTruncate('],['::writev(','FixtureLogWriteVectors('],['::close(','FixtureLogClose(']]){assert.equal(backend.split(a).length,2,a);backend=backend.replace(a,b);}
assert.equal((backend.match(/FixtureLogEnqueue\(/g)||[]).length,1);
let preceding=productionLogBatchBefore.replaceAll(/^#include[^\n]*\n/gm,'').replace('return queue;','return FixtureLogQueue(queue);').replace('dispatch_async(queue,','FixtureLogEnqueue(queue,')
    .replace('NSLog(@"[poc-touch] %s",msg)','FixtureSystemLog(@"[poc-touch] %s",msg)').replace('[df stringFromDate:[NSDate date]]','FixtureLogStamp()');
for(const [a,b] of [['::open(','FixtureLogOpen('],['::flock(','FixtureLogFlock('],['::fstat(','FixtureLogStat('],['::ftruncate(','FixtureLogTruncate('],['::write(','FixtureLogWrite('],['::close(','FixtureLogClose(']]){assert.equal(preceding.split(a).length,2,a);preceding=preceding.replace(a,b);}
preceding='namespace BeforeLogBatch {\n'+preceding+'\n}\n';
assert.doesNotMatch(preceding,/^#include/m);
const legacy=(await read('test/fixtures/production-log-before-c03av.inc')).replace('void POCLogf(','void FixtureLegacyLogf(').replace('NSLog(@"[poc-touch] %s", msg)','FixtureSystemLog(@"[poc-touch] %s", msg)').replace('[df stringFromDate:[NSDate date]]','FixtureLogStamp()');
const append=between(files.server,'static void TLinkScriptAppendLog(','static BOOL TLinkScriptStopRequested(');
const oldAppend=between(oldServer,'static void TLinkScriptAppendLog(','static BOOL TLinkScriptStopRequested(').replaceAll('TLinkScriptSession','LegacyScriptSession').replace('TLinkScriptAppendLog(','LegacyScriptAppendLog(').replace('POCLogf(','FixtureLegacyLogf(');
const fragments=[['ProductionLogAPI.h','extern "C" {\n'+api+'\n}\n'],['ProductionLogUnderTest.inc',backend],['ProductionLogBeforeBatch.inc',preceding],['ProductionLogLegacy.inc',legacy],['ScriptLogAppend.inc',append],['ScriptLogAppendLegacy.inc',oldAppend]];
const properties=between(files.server,'@interface TLinkScriptSession : NSObject','@implementation TLinkScriptSession');
fragments.push(['ScriptLogSession.inc',properties+'@implementation TLinkScriptSession\n@end\n']);
fragments.push(['ScriptLogLegacySession.inc',properties.replaceAll('TLinkScriptSession','LegacyScriptSession').replace('TLinkScriptLogBuffer *logs','NSMutableArray<NSString *> *logs')+'@implementation LegacyScriptSession\n@end\n']);
const status=between(files.server,'static NSDictionary *TLinkScriptStatusDictionary(','static void TLinkRunScriptSession(');
const oldStatus=between(oldServer,'static NSDictionary *TLinkScriptStatusDictionary(','static void TLinkRunScriptSession(').replaceAll('TLinkScriptSession','LegacyScriptSession').replace('TLinkScriptStatusDictionary(','LegacyScriptStatusDictionary(').replaceAll('sTLinkScriptSession','sLegacyScriptSession');
fragments.push(['ScriptLogStatus.inc',status],['ScriptLogStatusLegacy.inc',oldStatus]);
const clear=between(files.server,'static NSData *TLinkHandleClearScriptLog(','static NSData *TLinkHandleToast(');
fragments.push(['ScriptLogClear.inc',clear],['ScriptLogClearLegacy.inc',clear.replaceAll('TLinkScriptSession','LegacyScriptSession').replaceAll('sTLinkScriptSession','sLegacyScriptSession').replace('TLinkHandleClearScriptLog(','LegacyClearScriptLog(')]);
const hooks=(text,name)=>{
    const consoleHook=between(text,'    __weak TLinkScriptSession *weakSession = session;','    JSValue *device =');
    const deviceHook=between(text,'    device[@"log"] =','    device[@"toast"] =');
    return `static void ${name}(JSContext *context,TLinkScriptSession *session){\n${consoleHook}    JSValue *device=[JSValue valueWithNewObjectInContext:context];\n${deviceHook}    context[@"device"]=device;\n}\n`;
};
fragments.push(['ScriptLogHooks.inc',hooks(files.server,'FixtureLogHooks')]);
const oldHooks=hooks(oldServer,'LegacyLogHooks').replaceAll('TLinkScriptSession','LegacyScriptSession').replaceAll('TLinkScriptAppendLog','LegacyScriptAppendLog');
fragments.push(['ScriptLogHooksLegacy.inc',oldHooks]);
assert.ok(fragments.find(([name])=>name==='ProductionLogAPI.h')[1].startsWith('extern "C" {\n'));
assert.ok(fragments.find(([name])=>name==='ScriptLogSession.inc')[1].endsWith('@implementation TLinkScriptSession\n@end\n'));
console.log('Production logger source passed: exact complete server/injector/header reversals, bounded raw formatted queue, checked capped POSIX writer, session ring, status/evidence tails and three JS pools; root/HID/task bodies retained.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-production-log-'));
function run(cmd,args){const r=spawnSync(cmd,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${cmd} failed signal=${r.signal}`);}
try{
    await Promise.all(fragments.map(([name,text])=>writeFile(join(temp,name),text)));
    const windows=process.platform==='win32',cxx=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl.exe)$/i.test(basename(cxx));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/script-log-safety-test.cpp');
    run(cxx,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(cxx,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/production-log-runtime-test.mm'),'-o',native]);run(native,[temp]);
    }else console.log('macOS production log Foundation/GCD/POSIX/JSCore integration included in CI; not executed here.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-production-log-'));await rm(temp,{recursive:true,force:true});}
