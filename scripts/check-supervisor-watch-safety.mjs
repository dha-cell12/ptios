import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {legacySupervisorWatch,watchWait,watchExit,restoreSupervisorWatch} from './lib/supervisor-watch-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/StreamSupervisor.mm');restoreSupervisorWatch(source);
assert.match(watchWait(source),/do \{\s*w = waitpid\(pid, &status, 0\);\s*\} while \(w < 0 && errno == EINTR\);/);
assert.doesNotMatch(watchExit(source),/NSDate|timeIntervalSinceDate/);
assert.match(source,/self->_lastSpawnContinuous = TLinkHelperIO::nowMs\(\);/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-supervisor-watch-safety\.mjs/);
const adapt=s=>s.replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replaceAll('NSDate','FixtureDate')
    .replace('dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),','fixtureAfter(self, static_cast<int64_t>(delay * NSEC_PER_SEC),');
const constant=source.split('\n').find(line=>line.startsWith('static const NSTimeInterval kSCRespawnThrottle ='));assert.ok(constant);
console.log('Supervisor watcher source passed: exact-PID background EINTR retry, bounded continuous throttle and complete preceding exit/lifecycle/helper/transport/probe source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-watch-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await Promise.all([writeFile(join(temp,'WatchWaitUnderTest.inc'),watchWait(source)),writeFile(join(temp,'WatchExitUnderTest.inc'),adapt(watchExit(source))),
        writeFile(join(temp,'WatchExitLegacy.inc'),adapt(watchExit(legacySupervisorWatch))),writeFile(join(temp,'WatchThrottle.inc'),constant+'\n')]);
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/supervisor-watch-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',`/I${temp}`,file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-I',temp,file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/supervisor-watch-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen watcher Foundation/ARC/sanitizer timing/effect and real child-reap fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-watch-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
