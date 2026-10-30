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
const [socket,ipc,oldSocket,oldIPC]=await Promise.all(['tlinkauto-binary/SocketServer.mm','pccontrol/IPCMessagePort.xm','test/fixtures/vpn-ipc-daemon-before-c04h.inc','test/fixtures/vpn-ipc-receiver-before-c04h.inc'].map(read));
assert.equal(createHash('sha256').update(oldSocket).digest('hex'),'98a399ae2ebed67cf25b0aa6cf36c0769b55730bd0c00b0e5e80f627678c64b3');
assert.equal(createHash('sha256').update(oldIPC).digest('hex'),'4bd4de54d4e32065d2cb0b22e19ab574c8a4d0fa35dbfc68c2c36ca2628fae26');
const sender=between(socket,'// BEGIN isolated VPN IPC sender.','// BEGIN C01 IPC owner queues.');
const receiver=between(ipc,'// BEGIN isolated VPN IPC receiver.','void startIPCServerOnBackgroundThread()');
const decode=between(ipc,'        if(msgid==TLinkVPNIPCMessage){','\n        // Task 10');
const include='#include "../shared/TLinkVPNIPC.h"\n';
assert.equal(socket.replace(include,'').replace(sender,'').replace('    if(reply&&payload&&TLinkVPNIPCRequest((const uint8_t *)payload,strlen(payload)))return zx_vpnIPCQueue();\n','').replace('    if(waitForResponse&&TLinkVPNIPCRequest((const uint8_t *)payload,strlen(payload)))return zx_sendVPNIPC(payload);\n',''),oldSocket,'only dedicated VPN sender/queue routing changes complete daemon; admission/task/authority unchanged');
assert.equal(ipc.replace(include,'').replace(receiver,'').replace(decode,'').replace('    startVPNIPCServerOnBackgroundThread();\n',''),oldIPC,'only private VPN envelope, receiver/source/startup changes complete prior receiver');
assert.doesNotMatch(sender,/sendIPCMessage\(|ipcQueue\(|kTLinkautoIPCReadyMarkerPath|CMD_PING/);
assert.match(sender,/TLinkVPNIPCBudget\(TLinkCurrentNativeBudget\(\)\)/);
assert.match(receiver,/TLinkC01IPCAdmission admission\(active\)/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-ipc-safety\.mjs/);
console.log('VPN IPC source passed: dedicated sender/receiver, no legacy fallback, deadline envelope and complete previous task/admission/license/C01/legacy source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-ipc-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/vpn-ipc-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const constants=(await read('tlinkauto-binary/IPCConstants.h')).replaceAll('com.tlinkauto.tlinkautod.springboard',`test.${basename(temp)}.springboard`).replace('/var/mobile/Library/TLinkauto/ipc_ready',join(temp,'ipc-ready'));
        await Promise.all([
            writeFile(join(temp,'VPNIPCSender.inc'),sender.replaceAll('TLinkVPNIPCPortName','fixturePortName')),
            writeFile(join(temp,'VPNIPCReceiver.inc'),receiver.slice(0,receiver.indexOf('static void startVPNIPCServerOnBackgroundThread'))),
            writeFile(join(temp,'VPNIPCHandler.inc'),between(ipc,'static CFDataRef handleIPCMessage(','void startIPCServer()')),
            writeFile(join(temp,'C01IPCReceiver.inc'),between(ipc,'// BEGIN C01 isolated IPC receiver.','// END C01 isolated IPC receiver.')),
            writeFile(join(temp,'C01IPCQueues.inc'),between(socket,'// BEGIN C01 IPC owner queues.','// END C01 IPC owner queues.')),
            writeFile(join(temp,'C01IPCSender.inc'),between(socket,'// BEGIN C01 IPC sender.','// END C01 IPC sender.')),
            writeFile(join(temp,'VPNIPCConstants.h'),constants),writeFile(join(temp,'ipc-ready'),'ready')
        ]);
        const runtime=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/vpn-ipc-runtime-test.mm'),'-x','objective-c++',join(root,'pccontrol/SocketResponder.xm'),'-o',runtime]);run(runtime,[]);
    }else console.log('macOS actual three-port CF/run-loop and sender queue/runtime wired to CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-ipc-'));await rm(temp,{recursive:true,force:true});}
