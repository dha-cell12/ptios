import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {legacySupervisorChild,childSpawn,childRetirement,restoreSupervisorChild} from './lib/supervisor-child-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/StreamSupervisor.mm');restoreSupervisorChild(source);
const spawn=childSpawn(source),retire=childRetirement(source);
assert.ok(spawn.indexOf('NSObject *childIdentity')<spawn.indexOf('int rc = posix_spawn('));
assert.ok(spawn.indexOf('if (rc != 0)')<spawn.indexOf('self->_directChildIdentity = childIdentity;'));
assert.match(retire,/if \(!identity \|\| self->_directChildIdentity != identity\) return;\s*self->_directChildIdentity = nil;\s*\[self handleChildExit:/);
for(const [method,end] of [['stop','- (void)restart\n'],['restart','- (NSString *)sendLocalTaskLineLocked:']]){
    const begin=source.indexOf(`- (void)${method}\n`),finish=source.indexOf(end,begin+1);assert.ok(begin>=0&&finish>begin);
    const part=source.slice(begin,finish);assert.equal((part.match(/self->_directChildIdentity = nil;/g)||[]).length,1);
    const guard=part.indexOf(`if ([self helperBusyLocked:@"${method}"]) return;`),clear=part.indexOf('self->_directChildIdentity = nil;');
    assert.ok(guard>=0&&clear>guard);
}
assert.match(source,/if \(shouldReplace\) self->_directChildIdentity = nil;\s*int exitCode = \[self runPrivhelperEnsureStreamdLocked:shouldReplace\]/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-supervisor-child-safety\.mjs/);
const adapt=s=>s.replaceAll('dispatch_async(','fixtureAsync(self,').replaceAll('posix_spawn(','fixtureSpawn(self,').replaceAll('waitpid(','fixtureWait(self,').replaceAll('TLinkHelperIO::nowMs()','fixtureNow()');
const a=source.indexOf('- (void)handleChildExit:'),b=source.indexOf('\n@end',a);assert.ok(a>=0&&b>a);
const policy=source.slice(a,b).replaceAll('TLinkHelperIO::nowMs()','fixtureNow()');
const constant=source.split('\n').find(line=>line.startsWith('static const NSTimeInterval kSCRespawnThrottle ='));assert.ok(constant);
console.log('Supervisor child source passed: pre-spawn identity allocation, success-only publication, exact token retirement and explicit stop/restart/replacement invalidation with complete previous source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-child-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await Promise.all([writeFile(join(temp,'ChildUnderTest.inc'),adapt(spawn+retire)),writeFile(join(temp,'ChildLegacy.inc'),adapt(childSpawn(legacySupervisorChild))),
        writeFile(join(temp,'ChildExitPolicy.inc'),policy),writeFile(join(temp,'ChildThrottle.inc'),constant+'\n')]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/supervisor-child-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen child spawn/wait/retirement Foundation/GCD/ARC/sanitizer identity/real-child fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-child-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
