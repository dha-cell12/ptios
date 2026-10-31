import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {restoreBrokerControlPreflight,vpnControlPreflight} from './lib/vpn-control-preflight-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const hash=s=>createHash('sha256').update(s).digest('hex');
const reference=await read('vpn-broker/main.mm');
const waitReference=between(reference,'// BEGIN pending VPN manager operation admission.','static NSString *TLinkVPNBrokerResponse');
const enqueueReference=between(reference,'// BEGIN bounded VPN broker clients.','static void TLinkVPNBrokerRunServer');
const operations=await read('shared/TLinkVPNBrokerOperations.h');
const priorOperations=operations.replace('Stats stats;uint64_t lastId;size_t limit;','Stats stats;uint64_t lastId;')
    .replace('State(uint64_t cursor,size_t requestedLimit):lastId(cursor),limit(requestedLimit<Limit?requestedLimit:Limit){}','explicit State(uint64_t cursor):lastId(cursor){}')
    .replace('explicit TLinkVPNBrokerOperations(uint64_t lastTicket=0,size_t limit=Limit):state_(std::make_shared<State>(lastTicket,limit)){}','explicit TLinkVPNBrokerOperations(uint64_t lastTicket=0):state_(std::make_shared<State>(lastTicket)){}')
    .replace('state_->stats.active<state_->limit','state_->stats.active<Limit');
assert.equal(hash(priorOperations),'85c98df37fecc400fb1751d1483a75d022f6db26382a09eb67359db386745857','only bounded configurable capacity added to existing operation owner');
const cases=[
    {agent:false,path:'stream-app/app/TLinkVPNForegroundBroker.mm',prefix:'TLinkVPNForeground',constant:'kTLinkVPNForegroundBroker',wait:'TLinkVPNForegroundBrokerWait',response:'TLinkVPNForegroundBrokerResponse',timeout:'vpn_broker_operation_timeout',fixture:'vpn-foreground-before-c06h.inc',hash:'36688d853eaa9fd45cb49533e57032c6b328323acf315c6673a9a6c25038aa35'},
    {agent:true,path:'stream-app/vpnagent/main.mm',prefix:'TLinkVPNAgent',constant:'kTLinkVPNAgent',wait:'TLinkVPNAgentWait',response:'TLinkVPNAgentResponse',timeout:'vpnagent_operation_timeout',fixture:'vpn-agent-before-c06h.inc',hash:'f1010a22e8b6b258cf2d42c029d470f1d1c91a86ae7774895bd1064cbd937064'},
];
for(const item of cases){
    const {prefix,constant,response,timeout}=item;
    const [actual,before]=await Promise.all([read(item.path),read('test/fixtures/'+item.fixture)]);
    const source=restoreBrokerControlPreflight(actual,item.agent);
    item.source=actual;item.before=before;assert.equal(hash(before),item.hash);
    const wait=between(source,'// BEGIN pending VPN manager operation admission.',`static NSDictionary *${prefix}Preflight`);
    const enqueue=between(source,'// BEGIN bounded VPN broker clients.',`static void ${prefix}RunServer`);
    const mutations=between(source,'// BEGIN serialized broker mutations.',`static NSString *${prefix}DiagnosticsResponse`);
    assert.match(mutations,/mutations\(0, 1\)/);
    assert.match(mutations,/TLinkVPNBrokerStarterScope starter\{ticket\};[\s\S]*ticket->complete\(\);[\s\S]*completion\(value\)/);
    assert.equal(wait,waitReference.replaceAll('TLinkVPNBrokerOperationOwner',prefix+'OperationOwner').replaceAll('TLinkVPNBrokerWait',item.wait).replaceAll('vpn_broker_operation_timeout',timeout),'reuse complete root wait/operation ownership policy');
    assert.equal(enqueue,enqueueReference.replaceAll('TLinkVPNBrokerEnqueueClient',prefix+'EnqueueClient').replaceAll('TLinkVPNBrokerHandleClient',prefix+'HandleClient').replaceAll('[TLinkVPNBroker]','['+prefix+']'),'reuse complete root client ownership policy');
    let restored=source.replace(mutations,'').replace(`${prefix}SetConnected(requestedConnected, completion);`,'TLinkVPNSetConnected(requestedConnected, 20.0, completion);');
    for(const name of ['TLinkHelperClientAdmission','TLinkHelperSocketIO','TLinkVPNBrokerIngress','TLinkVPNBrokerBudget','TLinkVPNBrokerOperations'])restored=restored.replace(`#include "../../shared/${name}.h"\n`,'');
    restored=restored.replace(`static const size_t ${constant}MaxClients = 8;\n`,'')
        .replace(wait,between(before,'static NSDictionary *'+item.wait+'(',`static NSDictionary *${prefix}Preflight`))
        .replace(`static NSString *${prefix}DiagnosticsResponse(const TLinkVPNBrokerIngress::Window &request)`,`static NSString *${prefix}DiagnosticsResponse(void)`)
        .replace(`static NSString *${response}(NSString *command, const TLinkVPNBrokerIngress::Window &request)`,`static NSString *${response}(NSString *command)`)
        .replaceAll(`return ${prefix}DiagnosticsResponse(request);`,`return ${prefix}DiagnosticsResponse();`)
        .replaceAll('8.0, request);','8.0);').replaceAll('24.0, request);','24.0);')
        .replaceAll(`    if (!request.remaining(TLinkHelperIO::nowMs())) return @"-1;;${timeout}\\r\\n";\n`,'')
        .replace('\n\n    if ([clean isEqualToString:@"query"]) {','\n    if ([clean isEqualToString:@"query"]) {')
        .replace(`static void ${prefix}HandleClient(int client, uint64_t acceptedAt)\n{\n    const TLinkVPNBrokerIngress::Window ingress(acceptedAt);\n    const auto readOps = TLinkVPNBrokerIngress::posixReadOps();\n    if (!ingress.remaining(readOps.now(readOps.context))) return;`,`static void ${prefix}HandleClient(int client)\n{`)
        .replace('        size_t received = 0;\n        if (!TLinkVPNBrokerIngress::readChunk(readOps, client, buffer, capacity, ingress, received).ok()) return;\n        if (received == 0) break;','        ssize_t received = recv(client, buffer, capacity, 0);\n        if (received <= 0) break;')
        .replaceAll('    if (!ingress.remaining(readOps.now(readOps.context))) return;\n','')
        .replace(`${response}(request, ingress)`,`${response}(request)`);
    const output=between(restored,'    const auto writeOps =', '\n}\n\n// BEGIN bounded VPN broker clients.');
    restored=restored.replace(output,between(before,'    const uint8_t *cursor =','\n}\n\nstatic void '+prefix+'RunServer')).replace(enqueue,'');
    const indent=item.agent?'        ':'            ';
    restored=restored.replace(indent.slice(0,-4)+`TLinkHelperClientAdmission admission(${constant}MaxClients);\n`,'')
        .replace(indent+`${prefix}EnqueueClient(\n`+indent+'    admission, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), client);\n',
            item.agent?'        dispatch_async(\n            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{\n                @autoreleasepool {\n                    TLinkVPNAgentHandleClient(client);\n                }\n            });\n':indent+`${prefix}HandleClient(client);\n`);
    assert.equal(restored,before,'complete prior parser/replies/license/foreground/preflight/manager/listener/identity source');
}
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-trollstore-vpn-broker-safety\.mjs/);
console.log('TrollStore VPN broker source passed: narrow admission preflight, 6015/6016 bounded clients, accepted-time ingress/output/wait, pending manager tickets, one pending mutation and complete frozen authority/parser/diagnostics/identity source.');
function fixtureSources(item){
    const {prefix,constant,source,before,response,wait}=item;
    const normalize=s=>s.replaceAll(constant+'MaxRequest','kTLinkVPNBrokerMaxRequest').replaceAll(prefix+'HandleClient','TLinkVPNBrokerHandleClient').replaceAll(prefix+'EnqueueClient','TLinkVPNBrokerEnqueueClient');
    const adaptHandler=s=>normalize(s.replaceAll(response+'(request, ingress)','fixtureResponse(request)').replaceAll(response+'(request)','fixtureResponse(request)'));
    const actual=adaptHandler(between(source,`static void ${prefix}HandleClient`,`static void ${prefix}RunServer`))
        .replace('admission.acquire(','fixtureAcquire(admission,').replace('dispatch_async(queue,','fixtureDispatch(queue,').replace('(void)::close(fd);','fixtureClose(fd);').replaceAll('NSLog(','fixtureLog(')
        .replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replace('TLinkVPNBrokerIngress::posixReadOps()','fixtureReadOps()').replace('TLinkVPNBrokerBudget::posixWriteOps()','fixtureWriteOps()')
        .replace('[[NSString alloc] initWithData:requestData\n                                encoding:NSUTF8StringEncoding]','fixtureDecode(requestData)');
    assert.match(actual,/fixtureDecode\(requestData\)/);
    const legacy=adaptHandler(between(before,`static void ${prefix}HandleClient`,`static void ${prefix}RunServer`));
    const adaptWait=(s,current)=>{
        let value=s.replaceAll(wait,'TLinkVPNBrokerWait').replaceAll(response,'TLinkVPNBrokerResponse');
        if(current){
            value=value.replace(between(value,'static TLinkVPNBrokerOperations &'+prefix+'MutationOwner',`static void ${prefix}SetConnected`),'');
            value=value.replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replace('completion->wait(std::min(remaining, 250))','fixtureWait(*completion, std::min(remaining, 250))').replaceAll(prefix+'OperationOwner()','fixtureOperationOwner()').replaceAll(prefix+'MutationOwner()','fixtureMutationOwner()');
        }
        return value;
    };
    const active=item.agent?'':between(source,'static BOOL TLinkVPNForegroundAppActive','// BEGIN pending VPN manager operation admission.');
    const currentWait=active+adaptWait(between(source,'static NSDictionary *'+wait,`static void ${prefix}HandleClient`),true);
    const legacyWait=adaptWait(between(before,item.agent?'static NSDictionary *'+wait:'static BOOL TLinkVPNForegroundAppActive',`static void ${prefix}HandleClient`),false);
    assert.match(currentWait,/fixtureOperationOwner\(\)/);assert.match(currentWait,/fixtureMutationOwner\(\)/);assert.match(currentWait,/fixtureWait\(/);
    return {'VPNBrokerAdmissionUnderTest.inc':actual,'VPNBrokerHandlerLegacy.inc':legacy,'VPNBrokerWaitUnderTest.inc':currentWait,'VPNBrokerWaitLegacy.inc':legacyWait};
}
const control=vpnControlPreflight(await read('shared/TLinkVPNDiagnostics.mm'))
    .replaceAll('TLinkVPNEntitlementProbe()','fixtureEntitlements()').replaceAll('TLinkVPNFrameworkProbe()','fixtureFramework()');
for(const item of cases)item.fixtures={...fixtureSources(item),'VPNControlPreflightUnderTest.inc':control};
if(process.platform!=='darwin')console.log('macOS actual/frozen TrollStore broker socket/queue/manager Foundation/GCD/ARC/sanitizer cases included in CI; not run on this host.');
else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ts-vpn-'));
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    const compiler=process.env.CXX||'clang++';
    function compile(file,binary,agent){run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-DTLINK_FIXTURE_AGENT='+(agent?1:0),'-I',temp,join(root,file),'-o',binary]);run(binary,[]);}
    try{
        for(const item of cases){
            await Promise.all(Object.entries(item.fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
            console.log(`TrollStore VPN ${item.agent?'agent 6016':'foreground 6015'}: actual socket/lease/queue and frozen handler parity`);
            compile('test/vpn-broker-admission-runtime-test.mm',join(temp,item.agent?'agent-clients':'app-clients'),item.agent);
            compile('test/trollstore-vpn-broker-wait-runtime-test.mm',join(temp,item.agent?'agent-wait':'app-wait'),item.agent);
        }
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ts-vpn-'));await rm(temp,{recursive:true,force:true});}
}
