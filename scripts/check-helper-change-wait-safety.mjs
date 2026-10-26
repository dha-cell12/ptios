import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [server,client,protocol,runtime]=await Promise.all(['tlinkauto-jsd/TLinkJSHelperServer.mm','pccontrol/jsruntime/TLinkJSHelperClient.mm','pccontrol/jsruntime/TLinkJSHelperProtocol.mm','pccontrol/TLinkautoJSRuntime.mm'].map(read));
assert.match(protocol,/kTLinkJSHelperCmdWaitForChange = @"waitForChange"/);
assert.match(client,/waitForChangeAfterSequence[\s\S]*helper_not_bound[\s\S]*kTLinkJSHelperCmdWaitForChange/);
assert.match(server,/changeSequence = _statusChanges.sequence\(\)[\s\S]*pendingNativeRPC/);
assert.match(server,/Never retain the command owner[\s\S]*_statusChanges.wait/);
assert.match(server,/waitForChangeRequest:request deadline:deadline/);
assert.match(server,/_statusChanges.stop\(\)/);
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-helper-change-wait-safety\.mjs/);
const begin=runtime.indexOf('// BEGIN helper runtime wait loop.'),end=runtime.indexOf('// END helper runtime wait loop.',begin);
assert.ok(begin>=0&&end>begin);const implementation=runtime.slice(begin,end);
assert.match(implementation,/TLinkHelperRPCStatusError[\s\S]*TLinkHelperRPCDispatch[\s\S]*waitForChangeAfterSequence:sequence/);
assert.match(implementation,/TLinkHelperRuntimeHintError/);
assert.match(implementation,/setCancellationCheck:nil[\s\S]*releaseOwnedHandles/);
assert.match(runtime,/infrastructureFailure = \[helperError.userInfo\[@"helperFallbackSafe"\] boolValue\]/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-change-wait-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await writeFile(join(temp,'HelperRuntimeWaitUnderTest.inc'),implementation);
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'helper-change-wait.exe':'helper-change-wait'),file=join(root,'test/helper-change-wait-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const executable=join(temp,'helper-runtime-wait');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,
            join(root,'test/helper-runtime-wait-test.mm'),join(root,'pccontrol/TLinkTaskContext.mm'),join(root,'shared/TLinkHelperRPCFingerprint.mm'),'-o',executable]);
        run(executable,[temp]);
    }else console.log('macOS actual helper runtime loop fixture is included in CI; not run on this host.');

}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-change-wait-'));await rm(temp,{recursive:true,force:true});}
