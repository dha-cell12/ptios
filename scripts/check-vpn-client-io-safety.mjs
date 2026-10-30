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
const [source,before,legacy,header]=await Promise.all(['pccontrol/Connectivity.xm','test/fixtures/vpn-connectivity-before-c04f.inc','test/fixtures/vpn-broker-legacy-v1.inc','shared/TLinkVPNBrokerClientIO.h'].map(read));
assert.equal(createHash('sha256').update(before).digest('hex'),'43bd81226ed03494388cef5d302fe8fe3255aa19676516cebd972b29bcf36219');
const start='static NSString *zx_vpnBrokerRequest',end='NSString* wifiTaskFromRawData';
const actual=between(source,start,end),old=between(before,start,end);
assert.equal(old.trim(),legacy.slice(legacy.indexOf('\n')+1).trim());
assert.equal(source.replace('#include "../shared/TLinkVPNBrokerClientIO.h"\n','').replace(actual,old),before,'only VPN client transport/header changes complete previous Connectivity source');
assert.equal(actual.slice(actual.indexOf('    if ([clean hasPrefix:@"0;;"])')),old.slice(old.indexOf('    if ([clean hasPrefix:@"0;;"])')),'complete legacy success/error decoding stays frozen');
assert.match(actual,/Window window\(baseIO.now[\s\S]*socket\(AF_INET[\s\S]*Socket descriptor\(client\)/);
assert.match(actual,/descriptor.prepare\(\)[\s\S]*ClientIO::connect\([\s\S]*writeBytes\([\s\S]*readChunk\(/);
assert.doesNotMatch(actual,/SO_RCVTIMEO|SO_SNDTIMEO|\brecv\(|\bsend\(|\bclose\(client\)/);
assert.match(header,/std::min\(left,250\)/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-client-io-safety\.mjs/);
console.log('VPN client source passed: shared 30s connect/write/read deadline, scoped descriptor and complete previous parser/radio/VPN authority/error policy.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-client-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/vpn-client-io-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const adapt=s=>s.replace('socket(AF_INET, SOCK_STREAM, 0)','fixtureSocket(AF_INET, SOCK_STREAM, 0)');
        await Promise.all([
            writeFile(join(temp,'VPNClientUnderTest.inc'),adapt(actual).replace('TLinkHelperIO::Socket descriptor','FixtureSocket descriptor').replace('TLinkHelperIO::posixOps()','fixtureOps()').replace('TLinkVPNBrokerClientIO::posixConnectOps()','fixtureConnectOps()')),
            writeFile(join(temp,'VPNClientLegacy.inc'),adapt(old).replaceAll('close(client)','fixtureClose(client)').replace('connect(client,','fixtureConnect(client,').replace('send(client,','fixtureSend(client,').replace('recv(client,','fixtureReceive(client,'))
        ]);
        const runtime=join(temp,'vpn-client-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-client-io-runtime-test.mm'),'-o',runtime]);
        run(runtime,[]);
    }else console.log('macOS actual/frozen client Foundation/POSIX/ARC runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-client-'));await rm(temp,{recursive:true,force:true});}
