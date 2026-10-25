import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [server,transport]=await Promise.all(['tlinkauto-jsd/TLinkJSHelperServer.mm','shared/TLinkHelperSocketIO.h'].map(read));
assert.match(server,/DISPATCH_QUEUE_CONCURRENT/);
assert.match(server,/_clientAdmission.acquire\(client, acceptedAt/);
assert.match(server,/descriptor.release\(\)[\s\S]*dispatch_async\(self.clientQueue/);
assert.match(server,/lease->isOpen\(\) && deadline.remaining[\s\S]*takeDescriptor\(\)[\s\S]*handleClient:fd acceptedAt:lease->acceptedAt\(\)/);
assert.match(server,/lease->finish\(\)/);
assert.match(server,/Deadline deadline\(acceptedAt, ServerTimeoutMs\)/);
assert.match(server,/unique_lock<std::timed_mutex>[\s\S]*try_lock_for[\s\S]*_clientAdmission.isOpen\(\)[\s\S]*handleEnvelope/);
assert.match(server,/enqueueClient:client acceptedAt:TLinkHelperIO::nowMs\(\)/);
assert.match(server,/_clientAdmission.stop\(\)/);
assert.match(transport,/int release\(\)/);
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-helper-client-admission-safety\.mjs/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-client-admission-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'helper-client-admission.exe':'helper-client-admission'),file=join(root,'test/helper-client-admission-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
    run(binary,[]);

}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-client-admission-'));await rm(temp,{recursive:true,force:true});}
