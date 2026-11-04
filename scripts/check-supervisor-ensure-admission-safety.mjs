import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {ensureEntry,restoreSupervisorEnsure,restoreSupervisorEnsureHeader} from './lib/supervisor-ensure-admission-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/StreamSupervisor.mm');restoreSupervisorEnsure(source);restoreSupervisorEnsureHeader(await read('stream-app/app/StreamSupervisor.h'));
const entry=ensureEntry(source);
assert.ok(entry.indexOf('ensureLease->held()')<entry.indexOf('dispatch_async(_queue'));
assert.match(entry,/dispatch_async\(dispatch_get_main_queue\(\), \^\{ completion\(NO, @"supervisor_ensure_queue_full"\); \}\)/);
assert.match(entry,/Scope admissionScope\{ensureLease\};/);
assert.equal((entry.match(/ensureLease->release\(\)/g)||[]).length,3);
const native=await read('test/supervisor-helper-runtime-test.mm');assert.match(native,/queuedEnsureAdmissionCases\(\);/);assert.match(native,/fixturePendingEnsures/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-supervisor-ensure-admission-safety\.mjs/);
console.log('Supervisor ensure source passed: eight active/queued leases before enqueue, release before refusal/completion plus unwind scope, unchanged admitted work/header API and complete previous source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-ensure-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/supervisor-ensure-admission-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
    console.log('Extended complete-supervisor Foundation/GCD/ARC/sanitizer admission cases run in check-supervisor-helper-safety.mjs on macOS; not executed on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-ensure-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
