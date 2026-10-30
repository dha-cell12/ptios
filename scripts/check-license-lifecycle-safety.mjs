import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,join,resolve,basename} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const hash=s=>createHash('sha256').update(s).digest('hex');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const [source,before,header]=await Promise.all(['stream-app/app/LicenseLifecycleCoordinator.mm','test/fixtures/license-lifecycle-before-c06f.inc','stream-app/app/LicenseLifecycleCoordinator.h'].map(read));
assert.equal(hash(before),'652cac70147534280d3074e9f125a9a4c3caa22e44e6ed7ac65fcff849061290');
let restored=source;
const properties=between(source,'// BEGIN refresh decision ownership.','// END refresh decision ownership.')+'// END refresh decision ownership.\n';
restored=restored.replace(properties,'').replace('        _refreshDecisionQueue = dispatch_queue_create("com.tlinkauto.license-refresh-decision", DISPATCH_QUEUE_SERIAL);\n','')
    .replace('    if ([kind isEqualToString:@"refresh"]) return YES;\n','');
for(const [start,end] of [['- (void)updateDiagnostics:(NSDictionary *)values','- (void)deliverCompletion:'],['- (void)finishOperation:','- (void)publishLicenseChange:'],['- (void)recordRefreshFailure:','- (void)handleApplicationLaunch']])
    restored=restored.replace(between(restored,start,end),between(before,start,end));
assert.equal(restored,before,'complete UI snapshot/lifecycle/authority/activation/deactivation/reload and refresh policy source outside scoped sections preserved');
const refresh=between(source,'- (void)refreshForTrigger:','- (void)handleApplicationLaunch');
assert.ok(refresh.indexOf('beginOperation:@"refresh"')<refresh.indexOf('localStatus'));
assert.match(refresh,/dispatch_async\(self.refreshDecisionQueue[\s\S]*localStatus/);
assert.match(refresh,/if \(!\[self claimRefreshResult:identity\]\) return;/);
assert.match(source,/if \(self.refreshForceRequested\) return NO;/);
assert.match(source,/self.refreshResultClaimed && !ownsResult/);
assert.doesNotMatch(between(source,'- (void)appendRefreshHistoryEvent:','- (void)deliverCompletion:'),/\[self diagnostics\]/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-license-lifecycle-safety\.mjs/);
console.log('License lifecycle source passed: admission before verification, background single decision, force promotion, identity/result fences, serialized combined diagnostics/history and complete prior authority/UI source.');
if(process.platform!=='darwin')console.log('macOS complete current/frozen lifecycle Foundation/GCD/ARC/parity/race runtime included in CI; not run on this host.');
else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-license-lifecycle-'));
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        function adapt(s,legacy){
            s=s.slice(s.indexOf('NSString *const SCLicenseLifecycleDidChangeNotification'));
            s=s.replace('static NSString *const kTLinkLicenseLifecycleDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/license_lifecycle.plist";',`#define kTLinkLicenseLifecycleDiagnosticsPath ${legacy?'legacyPath':'currentPath'}`);
            if(legacy)s=s.replaceAll('SCLicenseLifecycleCoordinator','SCLegacyLifecycleCoordinator').replaceAll('SCLicenseLifecycleDidChangeNotification','SCLegacyLifecycleDidChangeNotification').replaceAll('kTLink','kLegacy').replaceAll('SCLicenseRequestDaemonReload','SCLegacyRequestDaemonReload');
            return s;
        }
        await Promise.all([writeFile(join(temp,'LifecycleUnderTest.inc'),adapt(source,false)),writeFile(join(temp,'LifecycleLegacy.inc'),adapt(before,true)),
            writeFile(join(temp,'LegacyLifecycle.h'),header.replaceAll('SCLicenseLifecycleCoordinator','SCLegacyLifecycleCoordinator').replaceAll('SCLicenseLifecycleDidChangeNotification','SCLegacyLifecycleDidChangeNotification'))]);
        const binary=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++11','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/license-lifecycle-runtime-test.mm'),'-o',binary]);run(binary,[]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-license-lifecycle-'));await rm(temp,{recursive:true,force:true});}
}
