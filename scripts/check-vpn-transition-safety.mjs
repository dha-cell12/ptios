import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const [source,before,header]=await Promise.all(['shared/TLinkVPNManager.mm','test/fixtures/vpn-manager-before-c04j.inc','shared/TLinkVPNTransition.h'].map(read));
assert.equal(createHash('sha256').update(before).digest('hex'),'04f18dd37285f9824187e42a6a6dbedc38cd374401d3b2e119d5da3a054367cb');
const helper=between(source,'// BEGIN owned VPN transition.','void TLinkVPNSetConnected(');
const old=between(before,'            __block id observer = nil;','\n        }];\n    });\n}');
assert.equal(source.replace('#include "TLinkVPNTransition.h"\n','').replace(helper,'').replace('            TLinkVPNBeginTransition(manager,connected,target,boundedTimeout,completion);',old),before,'only pending public transition timer/observer ownership changes complete manager/root/TrollStore source');
assert.doesNotMatch(helper,/dispatch_after|__block/);
assert.match(helper,/dispatch_resume\(timer\);[\s\S]*state->installTimer\(timer\)/);
assert.match(helper,/vpn_transition_timer_failed[\s\S]*addObserverForName[\s\S]*startVPNTunnelAndReturnError/);
assert.match(header,/finished_=true;[\s\S]*completion_=nil;[\s\S]*cancelTimer\(timer\);[\s\S]*removeObserver:observer[\s\S]*completion\(result\)/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-transition-safety\.mjs/);
console.log('VPN transition source passed: first-result mutex, cancellable one-shot timer, observer installation race/unwind cleanup and complete previous manager/profile/authority/private-backend source.');
if(process.platform!=='darwin')console.log('macOS actual/frozen transition Foundation/GCD/ARC lifetime/race runtime included in CI; not run on this host.');
else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-transition-'));
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        const legacy='static void LegacyTransition(NEVPNManager *manager,BOOL connected,NEVPNStatus target,NSTimeInterval boundedTimeout,TLinkVPNResultCompletion completion)\n{\n'+old+'\n}\n';
        await Promise.all([writeFile(join(temp,'VPNTransitionUnderTest.inc'),helper),writeFile(join(temp,'VPNTransitionLegacy.inc'),legacy)]);
        const binary=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/vpn-transition-runtime-test.mm'),'-o',binary]);run(binary,[]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-transition-'));await rm(temp,{recursive:true,force:true});}
}
