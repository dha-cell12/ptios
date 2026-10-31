import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {restoreVPNControlPreflight,restoreVPNControlPreflightHeader,vpnControlPreflight} from './lib/vpn-control-preflight-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [actual,old,previous]=await Promise.all(['shared/TLinkVPNDiagnostics.mm','test/fixtures/vpn-diagnostics-before-c04a.mm','test/fixtures/vpn-diagnostics-before-c04k.mm'].map(read));
const current=restoreVPNControlPreflight(actual);
restoreVPNControlPreflightHeader(await read('shared/TLinkVPNDiagnostics.h'));
assert.equal(createHash('sha256').update(old).digest('hex'),'7dcd41a5e6dde3988efb7525be61191d5e07e44c0fbc40d320c44d323ab3f7fb');
assert.equal(createHash('sha256').update(previous).digest('hex'),'269f402b73560ed3736d0b9df803f96c2684b6cbfbda59a2203d480e56e5fb1e');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const helper=between(current,'// BEGIN process-local immutable entitlement cache.','static NSDictionary *TLinkVPNEntitlementProbeUsingCache');
const wrapper=between(current,'static NSDictionary *TLinkVPNEntitlementProbe(void)','static NSDictionary *TLinkVPNFrameworkProbe');
const previousWrapper=between(previous,'static NSDictionary *TLinkVPNEntitlementProbe(void)','static NSDictionary *TLinkVPNFrameworkProbe');
assert.equal(current.replace(wrapper,previousWrapper),previous,'only complete immutable entitlement probe reuse changes the C04a diagnostics source');
assert.match(wrapper,/@synchronized \(cache\)[\s\S]*if \(completedProbe\) return completedProbe;[\s\S]*TLinkVPNEntitlementProbeUsingCache\(cache\);[\s\S]*if \(cache.count == 10\) completedProbe = probe;/);
const restored=current.replace(helper,'').replace(wrapper,'')
    .replace('static NSDictionary *TLinkVPNEntitlementProbeUsingCache(NSMutableDictionary *cache)','static NSDictionary *TLinkVPNEntitlementProbe(void)')
    .replace('cache.count == 10 ? NULL : SecTaskCreateFromSelf(kCFAllocatorDefault)','SecTaskCreateFromSelf(kCFAllocatorDefault)')
    .replace('if (!task && cache.count != 10)','if (!task)')
    .replaceAll('TLinkVPNReadEntitlement(','SecTaskCopyValueForEntitlement(')
    .replaceAll('cache, task,','task,').replace('if (task) CFRelease(task);','CFRelease(task);')
    .replace('[values addObject:[item copy]];','[values addObject:item];')
    .replace('[values addObject:[object copy]];','[values addObject:object];')
    .replace('return [values copy];','return values;');
assert.equal(restored,old,'complete diagnostics source: only entitlement memoization/immutable output changes');
assert.match(helper,/if \(\*error\) return value;[\s\S]*kCFPropertyListImmutable/);
assert.match(helper,/if \(!value \|\| immutable\) cache\[key\]/);
assert.match(helper,/catch \(\.\.\.\)[\s\S]*@catch[\s\S]*if \(immutable\) CFRelease\(immutable\)/);
assert.match(wrapper,/@synchronized \(cache\)[\s\S]*TLinkVPNEntitlementProbeUsingCache\(cache\)/);
assert.equal((between(current,'static NSDictionary *TLinkVPNEntitlementProbeUsingCache','static NSDictionary *TLinkVPNEntitlementProbe(void)').match(/TLinkVPNReadEntitlement\(/g)||[]).length,10);
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-vpn-diagnostics-cache-safety\.mjs/);
const adapt=s=>(between(s,'static NSString *const kTLinkVPNAPIEntitlement','NSString *TLinkVPNManagedProfileIdentifier')+
    between(s,'static NSArray<NSString *> *TLinkVPNNormalizedEntitlementValues','static NSDictionary *TLinkVPNFrameworkProbe'))
    .replace(/\bSecTaskRef\b/g,'FixtureSecTaskRef')
    .replaceAll('SecTaskCreateFromSelf(','fixtureCreateTask(').replaceAll('SecTaskCopyValueForEntitlement(','fixtureCopyEntitlement(')
    .replaceAll('CFPropertyListCreateDeepCopy(','fixtureDeepCopy(').replaceAll('CFRetain(','fixtureRetain(').replaceAll('CFRelease(','fixtureRelease(');
const extracted=[current,old,previous].map(adapt);
for(const source of extracted){assert.doesNotMatch(source,/\bSecTaskRef\b/);assert.match(source,/FixtureSecTaskRef task/);}
const fixture=await read('test/vpn-diagnostics-cache-runtime-test.mm');
assert.match(fixture,/using FixtureSecTaskRef = CFTypeRef;/);
assert.doesNotMatch(fixture,/(?:typedef[^;]*|using)\bSecTaskRef\b[^;]*;/);
const control=vpnControlPreflight(actual);
assert.doesNotMatch(control,/TLinkVPNPrivateCompatibilityProbe|TLinkVPNDiagnosticsSnapshot|NSDate|NSFileManager/);
console.log('VPN diagnostics cache source passed: narrow control preflight, ten process-local keys, success-only immutable values and completed probe, retry on errors/copy failures, serialized publication and complete prior dynamic diagnostics source.');
if(process.platform!=='darwin'){
    console.log('macOS actual/frozen entitlement/cache/CF ownership/concurrency runtime included in CI; not run on this host.');
}else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-diagnostics-'));
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        await Promise.all(['VPNEntitlementsUnderTest.inc','VPNEntitlementsLegacy.inc','VPNEntitlementsPrevious.inc'].map((name,index)=>writeFile(join(temp,name),extracted[index])));
        await writeFile(join(temp,'VPNControlPreflightUnderTest.inc'),control.replaceAll('TLinkVPNFrameworkProbe()','fixtureFrameworkProbe()'));
        const binary=join(temp,'vpn-diagnostics-runtime');
        run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-diagnostics-cache-runtime-test.mm'),'-o',binary]);
        run(binary,[]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-diagnostics-'));await rm(temp,{recursive:true,force:true});}
}
