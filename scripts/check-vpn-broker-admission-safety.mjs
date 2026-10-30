import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [current,old,owner]=await Promise.all(['vpn-broker/main.mm','test/fixtures/vpn-broker-before-c04b.inc','shared/TLinkHelperClientAdmission.h'].map(read));
assert.equal(createHash('sha256').update(old).digest('hex'),'7d85c63f3243f25761a98a80db049f04a82da03cb2255affb0b52e1d3717aaf7');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const handler=between(current,'static void TLinkVPNBrokerHandleClient','// BEGIN bounded VPN broker clients.');
const oldHandler=between(old,'static void TLinkVPNBrokerHandleClient','static void TLinkVPNBrokerRunServer');
assert.equal(handler,oldHandler.replace('        close(client);\n','').replace('    close(client);\n',''),'handler only borrows the lease-owned descriptor; exact old parser/I/O retained');
const enqueue=between(current,'// BEGIN bounded VPN broker clients.','static void TLinkVPNBrokerRunServer');
assert.match(enqueue,/Socket descriptor\(client\);[\s\S]*admission.acquire\(client, 0,[\s\S]*if \(!lease\) return;[\s\S]*descriptor.release\(\)[\s\S]*dispatch_async\(queue/);
assert.match(enqueue,/if \(lease->isOpen\(\)\) TLinkVPNBrokerHandleClient\(client\)/);
assert.match(enqueue,/@autoreleasepool[\s\S]*@catch[\s\S]*catch \(\.\.\.\)[\s\S]*lease->finish\(\)/);
assert.doesNotMatch(enqueue,/takeDescriptor|send\(|recv\(|semaphore_wait/);
assert.match(owner,/~Lease\(\)\{finish\(\);\}[\s\S]*finished_\.exchange\(true/);
const oldDispatch=between(old,'        dispatch_async(','    }\n    close(server);');
const newDispatch='        TLinkVPNBrokerEnqueueClient(\n            admission, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), client);\n';
const restored=current.replace('#include "../shared/TLinkHelperClientAdmission.h"\n','').replace('#include "../shared/TLinkHelperSocketIO.h"\n','')
    .replace('static const size_t kTLinkVPNBrokerMaxClients = 8;\n','').replace(enqueue,'').replace(handler,oldHandler)
    .replace('    TLinkHelperClientAdmission admission(kTLinkVPNBrokerMaxClients);\n','').replace(newDispatch,oldDispatch);
assert.equal(restored,old,'complete broker source preserves all response/license/manager/timeouts/listener behavior');
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-vpn-broker-admission-safety\.mjs/);
console.log('VPN broker admission source passed: eight slots before dispatch, socket/slot shared ownership, no rejection I/O, exception containment and complete prior broker/parser/authority source.');
if(process.platform!=='darwin'){
    console.log('macOS actual broker handler/admission with real sockets/GCD/ARC and controlled response provider included in CI; not run on this host.');
}else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-admission-'));
    const adapt=s=>s.replaceAll('TLinkVPNBrokerResponse(command)','fixtureResponse(command)');
    const actual=adapt(handler+enqueue).replace('admission.acquire(','fixtureAcquire(admission,')
        .replace('dispatch_async(queue,','fixtureDispatch(queue,').replace('(void)::close(fd);','fixtureClose(fd);').replaceAll('NSLog(','fixtureLog(');
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        await Promise.all([writeFile(join(temp,'VPNBrokerAdmissionUnderTest.inc'),actual),writeFile(join(temp,'VPNBrokerHandlerLegacy.inc'),adapt(oldHandler))]);
        const binary=join(temp,'vpn-broker-admission-runtime');
        run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-broker-admission-runtime-test.mm'),'-o',binary]);
        run(binary,[]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-admission-'));await rm(temp,{recursive:true,force:true});}
}
