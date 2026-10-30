import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y+b.length);};
const [source,before,header]=await Promise.all(['shared/TLinkVPNPrivateRequest.mm','test/fixtures/vpn-private-request-before-c06a.inc','shared/TLinkVPNHelperChild.h'].map(read));
assert.equal(createHash('sha256').update(before).digest('hex'),'5e00471542cf0f5e31851c3474081dfda7281c76afe85da8eb22417ab8ed192b');
const admission=between(source,'    // BEGIN bounded VPN helper admission.','    // END bounded VPN helper admission.');
const wait=between(source,'    // BEGIN bounded VPN helper wait.','    // END bounded VPN helper wait.');
const oldWait=between(before,'    int status = 0;','    } while (waited < 0 && errno == EINTR);');
const restored=source.replace('#include "TLinkVPNHelperChild.h"\n','').replace(admission+'\n','')
    .replace('    child.paths(requestPath.fileSystemRepresentation, resultPath.fileSystemRepresentation);\n','')
    .replace('    child.createdRequest();\n','')
    .replace('    if (spawnResult == 0) child.adopted(pid);\n','').replace(wait,oldWait);
assert.equal(restored,before,'complete trusted identity, directory/request/credential transport, spawn persona, healthy result parser and replies preserved');
assert.ok(source.indexOf('child.adopted(pid)')<source.indexOf('posix_spawnattr_destroy'));
assert.match(header,/::waitpid\(pid,&status,WNOHANG\)/);
assert.doesNotMatch(header,/waitpid\([^\n]*,0\)|::kill\(-/);
assert.match(header,/dispatch_resume\(state->timer\)/);
assert.match(header,/if\(state->pid<=0\)\{state->retire\(\);return;\}/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-helper-child-safety\.mjs/);
console.log('VPN helper child source passed: bounded wait and admission, exact child ownership, resumed deferred reaper and complete previous request/identity/persona/result source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-child-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/vpn-helper-child-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const adapt=s=>s.slice(s.indexOf('static NSString *const kTLinkVPNRequestDirectory'))
            .replace('static NSString *const kTLinkVPNRequestDirectory =\n    @"/var/mobile/Library/TLinkauto/tmp/vpn-private-requests";','')
            .replaceAll('kTLinkVPNRequestDirectory','fixtureDirectory')
            .replace('child.wait()','child.wait(fixtureTimeout,20)');
        await Promise.all([writeFile(join(temp,'VPNPrivateRequestUnderTest.inc'),adapt(source)),writeFile(join(temp,'VPNPrivateRequestLegacy.inc'),adapt(before))]);
        const runtime=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-helper-child-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
    }else console.log('macOS actual child/reaper/credential transport runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-child-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
