import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [verifier, authority, policy] = await Promise.all(['shared/TLinkLicenseVerifier.mm','license-authority/main.mm','shared/TLinkRootfullLicensePolicy.mm'].map(async p => (await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n')));
function between(source, a, b) { const x = source.indexOf(a), y = source.indexOf(b, x + a.length); assert.ok(x >= 0 && y > x, a); return source.slice(x, y); }
const adapter = between(verifier, '// BEGIN license hot-cache adapter.', '// END license hot-cache adapter.');
assert.doesNotMatch(adapter, /dispatch_sync/);
assert.match(policy, /TLinkLicenseCachedStatusDictionary/);
assert.ok(authority.indexOf('sAuthorityAdmission.acquire()') < authority.indexOf('dispatch_async(', authority.indexOf('sAuthorityAdmission.acquire()')));
assert.match(authority, /@finally \{ close\(client\); sAuthorityAdmission.release\(\); \}/);
const metrics = between(verifier, 'static const char *kTLinkLicenseDarwinNotification', 'NSString *TLinkLicenseDirectoryPath');
const perf = verifier.slice(verifier.indexOf('NSDictionary *TLinkLicensePerformanceDictionary(void)'));
const fixture = metrics + adapter.replaceAll('TLinkLicenseHotNowNs()', 'FixtureNow()').replace('notify_register_dispatch(', 'FixtureRegisterNotification(') + perf;
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot,'tlink-license-hot-'));
function run(command,args) {
 const r = spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});
 if(r.stdout)process.stdout.write(r.stdout); if(r.stderr)process.stderr.write(r.stderr);
 if(r.error)throw r.error; assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);
}
try {
 await writeFile(join(temp,'LicenseHotUnderTest.inc'), fixture);
 const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
 const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary = join(temp, windows ? 'license-hot.exe' : 'license-hot');
 const file = join(root,'test/license-hot-safety-test.cpp');
 run(compiler,msvc ? ['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
  : ['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
 run(binary,[]);
 if(process.platform === 'darwin') {
  const runtime=join(temp,'license-hot-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/license-hot-runtime-test.mm'),'-o',runtime]);
  run(runtime,[]);
 } else console.log('macOS actual license snapshot/dispatch/timer/invalidation integration added to both workflows; not run on Windows.');
} finally { assert.equal(dirname(temp),tempRoot); assert.ok(basename(temp).startsWith('tlink-license-hot-')); await rm(temp,{recursive:true,force:true}); }
