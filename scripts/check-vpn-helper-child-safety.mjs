import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {restoreVPNPrivateStop,restoreVPNPrivateCaller,vpnPrivateScriptCall} from './lib/vpn-private-stop-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y+b.length);};
const [source,before,header]=await Promise.all(['shared/TLinkVPNPrivateRequest.mm','test/fixtures/vpn-private-request-before-c06a.inc','shared/TLinkVPNHelperChild.h'].map(read));
const beforeStop=restoreVPNPrivateStop(source);
const stopBaseline=await read('test/fixtures/vpn-private-request-before-c06b.inc');
assert.equal(beforeStop,stopBaseline);
const caller=await read('stream-app/streamd/POCSocketServer.mm');restoreVPNPrivateCaller(caller);
assert.equal(createHash('sha256').update(before).digest('hex'),'5e00471542cf0f5e31851c3474081dfda7281c76afe85da8eb22417ab8ed192b');
const admission=between(beforeStop,'    // BEGIN bounded VPN helper admission.','    // END bounded VPN helper admission.');
const wait=between(beforeStop,'    // BEGIN bounded VPN helper wait.','    // END bounded VPN helper wait.');
const oldWait=between(before,'    int status = 0;','    } while (waited < 0 && errno == EINTR);');
const restored=beforeStop.replace('#include "TLinkVPNHelperChild.h"\n','').replace(admission+'\n','')
    .replace('    child.paths(requestPath.fileSystemRepresentation, resultPath.fileSystemRepresentation);\n','')
    .replace('    child.createdRequest();\n','')
    .replace('    if (spawnResult == 0) child.adopted(pid);\n','').replace(wait,oldWait);
assert.equal(restored,before,'complete trusted identity, directory/request/credential transport, spawn persona, healthy result parser and replies preserved');
assert.ok(source.indexOf('child.adopted(pid)')<source.indexOf('posix_spawnattr_destroy'));
assert.match(header,/::waitpid\(pid,&status,WNOHANG\)/);
assert.doesNotMatch(header,/waitpid\([^\n]*,0\)|::kill\(-/);
assert.match(header,/dispatch_resume\(state->timer\)/);
assert.match(header,/if\(state->pid<=0\|\|state->result.retired\)\{state->pid=0;state->retire\(\);return;\}/);
assert.match(header,/waitInto\(state_->ops,state_->pid,state_->result,timeout,grace,stop\)/);
assert.equal((header.match(/if\(stop.stopped\(\)\)/g)||[]).length,2);
const adapt=s=>s.slice(s.indexOf('static NSString *const kTLinkVPNRequestDirectory'))
    .replace('static NSString *const kTLinkVPNRequestDirectory =\n    @"/var/mobile/Library/TLinkauto/tmp/vpn-private-requests";','')
    .replaceAll('kTLinkVPNRequestDirectory','fixtureDirectory')
    .replace('child.wait(TLinkVPNHelperChild::TimeoutMs, TLinkVPNHelperChild::GraceMs, cancellation)','child.wait(fixtureTimeout,20,cancellation)')
    .replace('child.wait()','child.wait(fixtureTimeout,20)');
const scriptStart=caller.indexOf('static BOOL TLinkScriptStopRequested(TLinkScriptSession *session)\n{');
const scriptEnd=caller.indexOf('static void TLinkScriptCloseOpenFiles',scriptStart);
assert.ok(scriptStart>=0&&scriptEnd>scriptStart);
const scriptStop=caller.slice(scriptStart,scriptEnd);
// Public declarations remain global in the fixture. Qualify namespace-bound calls
// so ADL through NSString/NSDictionary cannot add those global declarations.
const script=scriptStop+'\nstatic NSDictionary *CallScript(TLinkScriptSession *strongSession,NSString *helperPath,NSDictionary *request)\n{\n    return '+vpnPrivateScriptCall.replace('TLinkVPNRunPrivateConfigurationHelperWithStop(', 'Current::TLinkVPNRunPrivateConfigurationHelperWithStop(')+';\n}\n';
const forwardingCall='return TLinkVPNRunPrivateConfigurationHelperWithStop(helperPath, configuration, nil);';
const currentSource=adapt(source);
assert.equal(currentSource.split(forwardingCall).length,2);
const nativeSources=[currentSource.replace(forwardingCall,'return Current::TLinkVPNRunPrivateConfigurationHelperWithStop(helperPath, configuration, nil);'),adapt(before)];
assert.ok(nativeSources.every(s=>!s.includes('kTLinkVPNRequestDirectory')));
assert.match(nativeSources[0],/child.wait\(fixtureTimeout,20,cancellation\)/);
const publicHeader=await read('shared/TLinkVPNPrivateRequest.h');
const blockTypedef='typedef BOOL (^TLinkVPNPrivateRequestShouldStop)(void);';
assert.ok(publicHeader.includes(blockTypedef));
const probeHeader=publicHeader.replace(/^#import[^\n]*\n/gm,'').replace(blockTypedef,'using TLinkVPNPrivateRequestShouldStop=std::function<BOOL()>;');
const forwardingWrapper=nativeSources[0].slice(nativeSources[0].lastIndexOf('NSDictionary *TLinkVPNRunPrivateConfigurationHelper('));
assert.match(forwardingWrapper,/return Current::TLinkVPNRunPrivateConfigurationHelperWithStop/);
const scriptWrapper=script.slice(script.indexOf('static NSDictionary *CallScript(')).replace('^BOOL {','[=]() -> BOOL {');
assert.match(scriptWrapper,/return Current::TLinkVPNRunPrivateConfigurationHelperWithStop/);
const lookupProbe=`#include <cassert>
#include <functional>
#define FOUNDATION_EXPORT extern
#define nil nullptr
using BOOL=bool;
struct NSString {};
struct NSDictionary {};
struct TLinkScriptSession {BOOL stopRequested=false;};
${probeHeader}
static unsigned calls=0;
static BOOL stopped=false;
static BOOL TLinkScriptStopRequested(TLinkScriptSession *session){return session&&session->stopRequested;}
namespace Current {
NSDictionary *TLinkVPNRunPrivateConfigurationHelperWithStop(NSString *path,NSDictionary *configuration,TLinkVPNPrivateRequestShouldStop stop){
    assert(path&&configuration);++calls;stopped=stop&&stop();return configuration;
}
${forwardingWrapper}
}
namespace Script {
${scriptWrapper}
}
int main(){NSString path;NSDictionary configuration;TLinkScriptSession session;
    assert(Current::TLinkVPNRunPrivateConfigurationHelper(&path,&configuration)==&configuration&&!stopped);
    assert(Script::CallScript(&session,&path,&configuration)==&configuration&&!stopped);
    session.stopRequested=true;
    assert(Script::CallScript(&session,&path,&configuration)==&configuration&&stopped&&calls==3);
}
`;
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-helper-child-safety\.mjs/);
console.log('VPN helper child source passed: caller stop/preflight and live script binding, bounded wait/admission, exact retirement across predicate unwind and complete previous request/server source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-child-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/vpn-helper-child-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    const lookupFile=join(temp,'namespace-lookup.cpp'),lookupBinary=join(temp,windows?'namespace-lookup.exe':'namespace-lookup');
    await writeFile(lookupFile,lookupProbe);
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',lookupFile,`/Fe${lookupBinary}`,`/Fo${join(temp,'namespace-lookup.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror',lookupFile,'-o',lookupBinary]);run(lookupBinary,[]);
    console.log('VPN helper fixture namespace lookup passed: actual forwarding/script wrappers with global public declarations and live stop binding.');
    if(process.platform==='darwin'){
        await Promise.all([writeFile(join(temp,'VPNPrivateRequestUnderTest.inc'),nativeSources[0]),writeFile(join(temp,'VPNPrivateRequestLegacy.inc'),nativeSources[1]),writeFile(join(temp,'VPNScriptStopUnderTest.inc'),script)]);
        const runtime=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-helper-child-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
    }else console.log('macOS actual child/reaper/credential transport runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-child-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
