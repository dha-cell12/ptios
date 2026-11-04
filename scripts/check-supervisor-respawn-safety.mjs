import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {respawnMethods,respawnFields,restoreSupervisorRespawn} from './lib/supervisor-respawn-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/StreamSupervisor.mm');restoreSupervisorRespawn(source);
const between=(a,b)=>{const x=source.indexOf(a),y=source.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return source.slice(x,y);};
const ensure=between('- (void)ensureServiceWithStartPermission:','- (void)stop\n');
const oneCancel=part=>assert.equal((part.match(/\[self cancelPendingRespawnLocked\]/g)||[]).length,1);
oneCancel(ensure);
assert.ok(ensure.indexOf('admitted = startPermission()')<ensure.indexOf('helperBusyLocked:@"ensure"'));
assert.ok(ensure.indexOf('helperBusyLocked:@"ensure"')<ensure.indexOf('[self cancelPendingRespawnLocked]'));
for(const [a,b,gate] of [['- (void)restart\n','- (NSString *)sendLocalTaskLineLocked:', 'helperBusyLocked:@"restart"'],['- (void)spawnLocked\n','- (void)handleChildExit:', 'helperBusyLocked:@"spawn"']]){
    const part=between(a,b);oneCancel(part);assert.ok(part.indexOf(gate)<part.indexOf('[self cancelPendingRespawnLocked]'));
}
const stop=between('- (void)stop\n','- (void)restart\n');oneCancel(stop);assert.ok(stop.indexOf('[self cancelPendingRespawnLocked]')<stop.indexOf('helperBusyLocked:@"stop"'));
oneCancel(source.slice(source.indexOf('- (void)handleChildExit:')));
const methods=respawnMethods(source);
assert.ok(methods.indexOf('dispatch_resume(timer)')<methods.indexOf('dispatch_source_set_timer(timer'));
assert.match(methods,/if \(self->_respawnIdentity != identity\) return;\s*\[self cancelPendingRespawnLocked\];/);
assert.match(methods,/DISPATCH_TIME_FOREVER, 0/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-supervisor-respawn-safety\.mjs/);
const adapt=s=>s.replaceAll('dispatch_source_t','FixtureTimer *').replaceAll('dispatch_source_create(','fixtureCreate(').replaceAll('dispatch_resume(','fixtureResume(')
    .replaceAll('dispatch_source_set_event_handler(','fixtureHandler(').replaceAll('dispatch_source_set_timer(','fixtureArm(').replaceAll('dispatch_source_cancel(','fixtureCancel(');
console.log('Supervisor respawn source passed: owned resumed timer, lifecycle cancellation after admission, token-fenced stale callbacks, retire-before-spawn and complete prior supervisor source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-respawn-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await Promise.all([writeFile(join(temp,'RespawnUnderTest.inc'),adapt(methods)),writeFile(join(temp,'RespawnFields.inc'),adapt(respawnFields)),
        writeFile(join(temp,'RespawnRealUnderTest.inc'),methods),writeFile(join(temp,'RespawnRealFields.inc'),respawnFields)]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/supervisor-respawn-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual owned respawn Foundation/GCD/ARC/sanitizer lifecycle/stale-callback/fault fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-respawn-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
