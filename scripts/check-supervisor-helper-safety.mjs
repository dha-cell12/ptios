import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const [source,before,owner,header]=await Promise.all(['stream-app/app/StreamSupervisor.mm','test/fixtures/supervisor-before-c06c.inc','shared/TLinkVPNHelperChild.h','stream-app/app/StreamSupervisor.h'].map(read));
assert.equal(createHash('sha256').update(before).digest('hex'),'851abce84156b80eabfab2dd110e8edd53861d91223b1b08a166f948bda929f4');
let restored=source;
for(const [start,end] of [['- (int)runPrivhelperKillStreamdLocked\n','- (int)runPrivhelperEnsureStreamdLocked:'],['- (int)runPrivhelperEnsureStreamdLocked:(BOOL)replaceExisting\n','- (BOOL)preparePortForSpawnLocked']]){
    const chunk=between(source,start,end),old=between(before,start,end);
    const admission=between(chunk,'    // BEGIN supervised helper owner.','    // END supervised helper owner.\n')+'    // END supervised helper owner.\n';
    const wait=between(chunk,'    // BEGIN supervised helper wait.','    // END supervised helper wait.\n')+'    // END supervised helper wait.';
    const attributes=between(chunk,'    int attrResult = posix_spawnattr_init(&attr);','    int persona =');
    const previous=chunk.replace(admission,'').replace(attributes,'    posix_spawnattr_init(&attr);\n')
        .replace('    if (rc == 0) child.adopted(pid);\n','')
        .replace(wait,'    int status = 0;\n    pid_t w = waitpid(pid, &status, 0);\n    int exitCode = -1;');
    assert.equal(previous,old,'complete helper argv/persona/path/return/log source: '+start);
    assert.doesNotMatch(chunk,/waitpid\(/);assert.match(chunk,/child.adopted\(pid\)/);
    restored=restored.replace(chunk,old);
}
const fence=between(restored,'// BEGIN supervisor helper fence.','// END supervisor helper fence.\n')+'// END supervisor helper fence.\n\n';
restored=restored.replace('#include "../../shared/TLinkVPNHelperChild.h"\n','').replace('#include "../../shared/TLinkSupervisorHelper.h"\n','').replace(fence,'')
    .replace('        if ([self helperBusyLocked:@"ensure"]) {\n            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"supervisor_helper_pending"); });\n            return;\n        }\n','')
    .replace('        if ([self helperBusyLocked:@"stop"]) return;\n','').replace('        if ([self helperBusyLocked:@"restart"]) return;\n','')
    .replace('    if ([self helperBusyLocked:@"spawn"]) return;\n','').replace('    if ([self helperBusyLocked:@"spawn cleanup"]) return NO;\n','');
assert.equal(restored,before,'complete supervisor probe/shutdown/direct daemon/watchdog/delegate/lifecycle source preserved');
assert.match(owner,/std::shared_ptr<void> lifetime/);
assert.match(source,/Owner child\(TLinkVPNHelperChild::posixOps\(\), helperLease\)/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-supervisor-helper-safety\.mjs/);
console.log('Supervisor helper source passed: bounded helper owners, retained single lane, lifecycle/fallback busy fences, checked spawn attributes and full previous supervisor source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-supervisor-helper-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/supervisor-helper-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const adapt=s=>s.slice(s.indexOf('static const NSTimeInterval kSCRespawnThrottle'))
            .replaceAll('TLinkVPNHelperChild::posixOps(), helperLease','fixtureOps(), helperLease').replaceAll('child.wait()','child.wait(fixtureTimeout,20)');
        const legacy=adapt(before).replaceAll('SCStreamSupervisor','SCLegacySupervisor').replaceAll('kSCRespawnThrottle','kLegacyRespawnThrottle')
            .replaceAll('kSCRequiredStreamdServiceMarker','kLegacyRequiredStreamdServiceMarker').replaceAll('kSCRequiredVPNServiceMarker','kLegacyRequiredVPNServiceMarker');
        await Promise.all([writeFile(join(temp,'SupervisorUnderTest.inc'),adapt(source)),writeFile(join(temp,'SupervisorLegacy.inc'),legacy),
            writeFile(join(temp,'LegacySupervisor.h'),header.replaceAll('SCStreamSupervisor','SCLegacySupervisor'))]);
        const runtime=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/supervisor-helper-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
    }else console.log('macOS complete current/frozen supervisor/helper lifecycle runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-supervisor-helper-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
