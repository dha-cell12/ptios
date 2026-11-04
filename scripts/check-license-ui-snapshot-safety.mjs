import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {legacyUISnapshot,uiSnapshotMethod,restoreUISnapshot} from './lib/license-ui-snapshot-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/LicenseLifecycleCoordinator.mm');restoreUISnapshot(source);
const method=uiSnapshotMethod(source);
assert.equal((method.match(/dispatch_async\(self.uiSnapshotQueue/g)||[]).length,1);
assert.match(method,/for \(;;\) \{\s*@autoreleasepool/);
assert.match(method,/NSString \*requestedReason = \[reason copy\]/);
assert.match(method,/if \(!self.uiSnapshotRefreshPending\) \{\s*self.uiSnapshotRefreshInFlight = NO;\s*return;/);
assert.match(method,/if \(published\) \{\s*dispatch_async\(dispatch_get_main_queue/);
assert.doesNotMatch(method,/pendingReason.length|__block/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-license-ui-snapshot-safety\.mjs/);
const adapt=s=>s.replaceAll('dispatch_async(','fixtureAsync(self,').replaceAll('TLinkLicenseStatusDictionary()','[self statusProvider]').replaceAll('TLinkLicensePerformanceDictionary()','[self performanceProvider]');
console.log('License UI snapshot source passed: one gated worker, latest pending handoff, per-pass pool, immutable reason and exception-safe gate/ready notification with complete prior coordinator source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-license-ui-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await Promise.all([writeFile(join(temp,'UISnapshotUnderTest.inc'),adapt(method)),writeFile(join(temp,'UISnapshotLegacy.inc'),adapt(legacyUISnapshot))]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/license-ui-snapshot-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen UI snapshot Foundation/GCD/ARC/sanitizer fault/pending/handoff fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-license-ui-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
