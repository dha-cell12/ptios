import {restoreConsoleSchedule,consoleScheduleSpecs} from './lib/console-schedule-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const source=await read(consoleScheduleSpecs.file);restoreConsoleSchedule(source);
assert.doesNotMatch(source,/_logDrainScheduled/,'no obsolete field references remain, including the real constructor');
const named=name=>consoleScheduleSpecs.parts.find(part=>part.name===name);
for(const name of ['entry','drain','publication'])assert.equal(named(name).before,await read(`test/fixtures/console-schedule-${name}-before-c03bb.inc`));
assert.match(named('entry').current,/shared_ptr<TLinkConsoleLogPermit> permit;[\s\S]*NSData \*data/);
assert.match(named('publication').current,/shared_ptr<TLinkConsoleDrainTicket> ticket;[\s\S]*os_unfair_lock_lock[\s\S]*_logSchedule.prepare\(\)[\s\S]*dispatch_async[\s\S]*ticket.use_count\(\)==1[\s\S]*@finally[\s\S]*pop_back\(\)[\s\S]*rollback\(lease\)[\s\S]*os_unfair_lock_unlock/);
assert.match(named('drain').current,/retire\(token\)\)retired.swap[\s\S]*os_unfair_lock_unlock[\s\S]*entry.reset\(\)/);
assert.match(named('drain').current,/_logSchedule.matches\(token\)[\s\S]*batch.swap\(_logPending\)/);
assert.match(named('finish').current,/dispatch_sync[\s\S]*\[self drainConsoleLogs\];[\s\S]*snapshot\(\)/);
const runner=await read('scripts/check-console-log-safety.mjs'),fixture=await read('test/console-log-runtime-test.mm');
assert.match(runner,/replace\('dispatch_async\(_logQueue,','ConsoleEnqueue\(_logQueue,'\)/);
assert.match(runner,/between\(actualSource,'struct TLinkConsoleLogEntry/);
assert.match(fixture,/TLinkConsoleDrainSchedule _logSchedule/);assert.match(fixture,/consoleScheduleRuntimeCases\(root\)/);
console.log('Root console transaction source passed: complete previous runtime/authority reversal, rollback/unlock order, actual payload-before-permit fields, stale token checks and forced terminal drain.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-console-schedule-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/console-schedule-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    console.log('Actual root Foundation/GCD/JSCore enqueue/discard/stale/close/payload fault cases share the existing macOS console runtime; Apple execution requires CI.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-console-schedule-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
