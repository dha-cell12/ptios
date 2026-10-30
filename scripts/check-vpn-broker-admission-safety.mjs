import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [actualSource,old,owner,beforeIngress,ingress,beforeBudget,budget]=await Promise.all(['vpn-broker/main.mm','test/fixtures/vpn-broker-before-c04b.inc','shared/TLinkHelperClientAdmission.h','test/fixtures/vpn-broker-before-c04c.inc','shared/TLinkVPNBrokerIngress.h','test/fixtures/vpn-broker-before-c04d.inc','shared/TLinkVPNBrokerBudget.h'].map(read));
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
assert.equal(createHash('sha256').update(beforeBudget).digest('hex'),'dcbe39ad964877613536d525a21ea04bb704d95903a7be9487b31a00192c30f0');
const actualWait=between(actualSource,'static NSDictionary *TLinkVPNBrokerWait(','static NSString *TLinkVPNBrokerResponse');
const oldWait=between(beforeBudget,'static NSDictionary *TLinkVPNBrokerWait(','static NSString *TLinkVPNBrokerResponse');
const actualOutput=between(actualSource,'    const auto writeOps =','\n}\n\n// BEGIN bounded VPN broker clients.');
const oldOutput=between(beforeBudget,'    const uint8_t *bytes = (const uint8_t *)responseData.bytes;','\n}\n\n// BEGIN bounded VPN broker clients.');
const ingressSource=actualSource.replace('#include "../shared/TLinkVPNBrokerBudget.h"\n','').replace(actualWait,oldWait)
    .replace('static NSString *TLinkVPNBrokerResponse(NSString *command, const TLinkVPNBrokerIngress::Window &request)','static NSString *TLinkVPNBrokerResponse(NSString *command)')
    .replaceAll('    if (!request.remaining(TLinkHelperIO::nowMs())) return @"-1;;vpn_broker_operation_timeout\\r\\n";\n','')
    .replaceAll('8.0, request);','8.0);').replace('24.0, request);','24.0);')
    .replace('    NSString *response = TLinkVPNBrokerResponse(command, ingress);\n    if (!ingress.remaining(readOps.now(readOps.context))) return;', '    NSString *response = TLinkVPNBrokerResponse(command);')
    .replace(actualOutput,oldOutput);
assert.equal(ingressSource,beforeBudget,'complete broker: only synchronized wait/phase budget, expiry gates and output deadline change');
assert.equal((actualSource.match(/if \(!request.remaining\(TLinkHelperIO::nowMs\(\)\)\) return/g)||[]).length,2,'gate before and after ordinary authority work');
assert.doesNotMatch(actualWait,/__block|dispatch_semaphore_t/);
assert.match(actualWait,/WaitWindow[\s\S]*TLinkVPNBrokerCompletionScope[\s\S]*operation\([\s\S]*completion->wait\(std::min\(remaining, 250\)\)/);
assert.match(budget,/if\(closed_\|\|ready_\)return;[\s\S]*value_=value;ready_=true/);
assert.match(budget,/finishChecked[\s\S]*lock_guard[\s\S]*accepted=timely\(\)/);
assert.match(budget,/MSG_DONTWAIT[\s\S]*::send/);
assert.equal(createHash('sha256').update(beforeIngress).digest('hex'),'6d29f36a4e5898860201eef7223b6f077f663b24170bfb5bc6465a2fff524930');
const current=ingressSource.replace('#include "../shared/TLinkVPNBrokerIngress.h"\n','')
    .replace('static void TLinkVPNBrokerHandleClient(int client, uint64_t acceptedAt)\n{\n    const TLinkVPNBrokerIngress::Window ingress(acceptedAt);\n    const auto readOps = TLinkVPNBrokerIngress::posixReadOps();\n    if (!ingress.remaining(readOps.now(readOps.context))) return;', 'static void TLinkVPNBrokerHandleClient(int client)\n{')
    .replace('        size_t received = 0;\n        if (!TLinkVPNBrokerIngress::readChunk(readOps, client, buffer, capacity, ingress, received).ok()) return;\n        if (received == 0) break;', '        ssize_t received = recv(client, buffer, capacity, 0);\n        if (received <= 0) break;')
    .replace('    if (!ingress.remaining(readOps.now(readOps.context))) return;\n    NSString *response', '    NSString *response')
    .replace('admission.acquire(client, TLinkHelperIO::nowMs(),','admission.acquire(client, 0,')
    .replace('TLinkVPNBrokerHandleClient(client, lease->acceptedAt());','TLinkVPNBrokerHandleClient(client);');
assert.equal(current,beforeIngress,'complete broker: only accepted-time ingress, nonblocking chunk read and pre-dispatch expiry checks change');
assert.equal(createHash('sha256').update(old).digest('hex'),'7d85c63f3243f25761a98a80db049f04a82da03cb2255affb0b52e1d3717aaf7');
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
assert.match(ingress,/TimeoutMs=30000/);
assert.match(ingress,/now<acceptedAt\?0:deadline.remaining\(now\)/);
assert.match(ingress,/::recv\(fd,bytes,count,MSG_DONTWAIT\)/);
assert.equal((ingress.match(/window.remaining\(ops.now\(ops.context\)\)/g)||[]).length,2);
assert.match(ingress,/waitReady\(ops,fd,false,window.deadline\)/);
assert.ok(actualSource.includes('[[NSString alloc] initWithData:requestData\n                              encoding:NSUTF8StringEncoding]'),'actual decoder hook exists without changing ordinary decoding');
console.log('VPN broker source passed: eight leases, shared ingress/wait/output window, synchronized completion/abandonment, nonblocking socket IO and complete prior command/authority/encoding/listener source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-admission-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const core=join(temp,windows?'vpn-ingress.exe':'vpn-ingress'),file=join(root,'test/vpn-broker-ingress-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${core}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',core]);
    run(core,[]);
    const budgetCore=join(temp,windows?'vpn-budget.exe':'vpn-budget'),budgetFile=join(root,'test/vpn-broker-budget-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',budgetFile,`/Fe${budgetCore}`,`/Fo${join(temp,'budget.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',budgetFile,'-o',budgetCore]);
    run(budgetCore,[]);
    if(process.platform!=='darwin'){
        console.log('macOS actual broker handler/admission with real sockets/GCD/ARC and controlled response provider included in CI; not run on this host.');
    }else{
    const adapt=s=>s.replaceAll('TLinkVPNBrokerResponse(command)','fixtureResponse(command)').replaceAll('TLinkVPNBrokerResponse(command, ingress)','fixtureResponse(command)');
    const actual=adapt(between(actualSource,'static void TLinkVPNBrokerHandleClient','static void TLinkVPNBrokerRunServer')).replace('admission.acquire(','fixtureAcquire(admission,')
        .replace('dispatch_async(queue,','fixtureDispatch(queue,').replace('(void)::close(fd);','fixtureClose(fd);').replaceAll('NSLog(','fixtureLog(')
        .replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replace('TLinkVPNBrokerIngress::posixReadOps()','fixtureReadOps()').replace('TLinkVPNBrokerBudget::posixWriteOps()','fixtureWriteOps()')
        .replace('[[NSString alloc] initWithData:requestData\n                              encoding:NSUTF8StringEncoding]', 'fixtureDecode(requestData)');
        await Promise.all([writeFile(join(temp,'VPNBrokerAdmissionUnderTest.inc'),actual),writeFile(join(temp,'VPNBrokerHandlerLegacy.inc'),adapt(oldHandler))]);
        const binary=join(temp,'vpn-broker-admission-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-broker-admission-runtime-test.mm'),'-o',binary]);
        run(binary,[]);
        await Promise.all([
            writeFile(join(temp,'VPNBrokerWaitUnderTest.inc'),between(actualSource,'static NSDictionary *TLinkVPNBrokerWait(','static void TLinkVPNBrokerHandleClient').replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replace('completion->wait(std::min(remaining, 250))','fixtureWait(*completion, std::min(remaining, 250))')),
            writeFile(join(temp,'VPNBrokerWaitLegacy.inc'),between(beforeBudget,'static NSDictionary *TLinkVPNBrokerWait(','static void TLinkVPNBrokerHandleClient'))
        ]);
        const waitBinary=join(temp,'vpn-broker-wait-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-broker-wait-runtime-test.mm'),'-o',waitBinary]);
        run(waitBinary,[]);
    }
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-admission-'));await rm(temp,{recursive:true,force:true});}
