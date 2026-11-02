import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {supervisorProbe,legacySupervisorProbe,restoreSupervisorProbe} from './lib/supervisor-probe-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/StreamSupervisor.mm');restoreSupervisorProbe(source);
const entry=supervisorProbe(source),probe=entry.slice(entry.indexOf('- (BOOL)probeTaskServerAndUpdateLocked:'));
assert.equal((entry.match(/sendLocalTaskLineLocked:@"60\\n"/g)||[]).length,1);
assert.equal((probe.match(/\[self streamdHelloStatusLocked\]/g)||[]).length,1);
assert.doesNotMatch(probe,/streamdPidFromHelloStatusLocked|streamdLaunchPathFromHelloStatusLocked/);
assert.ok(probe.indexOf('if (status.length == 0)')<probe.indexOf('[self streamdHelloStatusLocked]'));
const constants=source.slice(source.indexOf('static NSString *const kSCRequiredStreamdServiceMarker'),source.indexOf('@implementation SCStreamSupervisor'));
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-supervisor-probe-safety\.mjs/);
console.log('Supervisor probe source passed: one probe-local hello, same-response PID/path, unchanged decision/effect source and complete prior supervisor hash.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-probe-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const adapt=s=>s.replaceAll('proc_pidpath(','fixtureProcPath(').replaceAll('[NSJSONSerialization JSONObjectWithData:','[FixtureJSON JSONObjectWithData:');
    await Promise.all([writeFile(join(temp,'SupervisorProbeUnderTest.inc'),adapt(entry)),writeFile(join(temp,'SupervisorProbeLegacy.inc'),adapt(legacySupervisorProbe)),writeFile(join(temp,'SupervisorProbeConstants.inc'),constants)]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/supervisor-probe-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS complete actual/frozen probe Foundation/ARC/sanitizer parity and same-response fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-probe-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
