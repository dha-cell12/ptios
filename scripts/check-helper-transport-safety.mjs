import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [server,client,header]=await Promise.all(['tlinkauto-jsd/TLinkJSHelperServer.mm','pccontrol/jsruntime/TLinkJSHelperClient.mm','shared/TLinkHelperSocketIO.h'].map(read));
const between=(source,a,b)=>{const x=source.indexOf(a),y=source.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return source.slice(x,y);};
const admission=between(server,'// BEGIN helper socket client admission.','// END helper socket client admission.');
const owner=between(server,'// BEGIN helper socket client ownership.','// END helper socket client ownership.');
const error=between(server,'- (NSDictionary *)errorEnvelopeForRequest:','- (NSDictionary *)handleEnvelope:');
const clientImplementation=client.slice(client.indexOf('@interface TLinkJSHelperClient ()'));
assert.match(client,/Deadline deadline\(nowMs\(\), timeoutMs\)/);
assert.match(client,/connectUnix[\s\S]*writeFrame[\s\S]*readFrame[\s\S]*@finally \{ socket.close/);
assert.match(owner,/readFrame[\s\S]*deserializeEnvelope[\s\S]*deadline.remaining\(nowMs\(\)\)[\s\S]*handleEnvelope/);
assert.match(owner,/responseData.length > MaxFrameBytes[\s\S]*frame_too_large/);
assert.match(owner,/@finally \{ socket.close/);
assert.doesNotMatch(client,/SO_RCVTIMEO|SO_SNDTIMEO|while \(remaining|read\(sock|write\(sock/);
assert.doesNotMatch(server,/readAllFromClient/);
assert.match(header,/O_NONBLOCK/);assert.match(header,/SO_NOSIGPIPE/);assert.match(header,/MSG_NOSIGNAL/);
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-helper-transport-safety\.mjs/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-transport-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await writeFile(join(temp,'HelperTransportServerUnderTest.inc'),owner+error);
    await writeFile(join(temp,'HelperClientAdmissionUnderTest.inc'),admission);
    await writeFile(join(temp,'HelperTransportClientUnderTest.inc'),clientImplementation);
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'helper-transport.exe':'helper-transport'),file=join(root,'test/helper-transport-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const executable=join(temp,'helper-transport-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/helper-transport-runtime-test.mm'),join(root,'pccontrol/jsruntime/TLinkJSHelperProtocol.mm'),'-o',executable]);
        run(executable,[temp]);
    }else console.log('macOS actual helper client/server socket/identity/cleanup integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-transport-'));await rm(temp,{recursive:true,force:true});}
