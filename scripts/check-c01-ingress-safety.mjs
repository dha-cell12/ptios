import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [socket,task,ipc,runtimeSource]=await Promise.all(['tlinkauto-binary/SocketServer.mm','pccontrol/Task.xm','pccontrol/IPCMessagePort.xm','test/c01-ingress-runtime-test.mm'].map(read));
function section(text,a,b){const start=text.indexOf(a),end=text.indexOf(b,start+a.length);assert.ok(start>=0&&end>start,a);return text.slice(start,end);}
const work=section(socket,'// BEGIN socket work adapter.','// END socket work adapter.');
assert.ok(work.indexOf('TLinkC01TaskBudget(')<work.indexOf('dispatch_async(workQueue,'));
assert.ok(work.indexOf('TLinkC01LaneAvailable(')<work.indexOf('TLinkC01TaskBudget('));
assert.match(work,/workQueue=imageTask\?zx_imageTaskQueue\(\):zx_taskQueue\(\)/);
assert.match(work,/if\(imageTask\)--gPendingImageTasks/);
assert.match(work,/TLinkNativeBudgetScope ingressScope\(requestBudget\)/);
assert.doesNotMatch(socket,/TLinkNativeDispatchSync\(ipcQueue\(\)/);
assert.match(ipc,/startC01IPCServerOnBackgroundThread\(\);/);
const daemonConstants=await read('tlinkauto-binary/IPCConstants.h'),receiverConstants=await read('pccontrol/IPCConstants.h');
const portName=text=>text.match(/kTLinkautoC01IPCPortName\s*=\s*CFSTR\("([^"]+)"\)/)?.[1];
assert.ok(portName(daemonConstants));assert.equal(portName(daemonConstants),portName(receiverConstants));
assert.match(socket,/c01Cancellation->cancel\(\)/);assert.doesNotMatch(socket,/dispatch_sync\(ipcQueue\(\)/);
const entry=section(task,'void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)\n{','    //for touching');
assert.ok(entry.indexOf('TLinkC01TaskBudget(')<entry.indexOf('TLinkRootfullLicenseTaskAllowed('));
assert.ok(ipc.indexOf('TLinkC01Decode(')<ipc.indexOf('NSString *command'));
const sender=section(socket,'// BEGIN C01 IPC sender.','// END C01 IPC sender.');
assert.match(sender,/bounded \? TLinkC01IPCMessage/);
assert.match(sender,/bounded\?kTLinkautoC01IPCPortName:kTLinkautoIPCPortName/);
assert.match(sender,/!bounded && waitForResponse/);assert.match(sender,/No retry as unbounded legacy work/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-c01-ingress-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 // Compile message IDs against the macOS fixture's own portable imports on every
 // host, so missing shared dependencies fail even when Foundation is unavailable.
 const portableImports=[...runtimeSource.matchAll(/^#include "(\.\.\/shared\/[^"\n]+)"/gm)].map(match=>
  `#include ${JSON.stringify(resolve(root,'test',match[1]).replaceAll('\\','/'))}`);
 const messageIDs=[...new Set([...sender.matchAll(/\bTLink[A-Za-z0-9_]*Message\b/g)].map(match=>match[0]))];
 assert.ok(portableImports.length&&messageIDs.length);
 const dependencyProbe=join(temp,'C01FixtureDependencies.h');
 await writeFile(dependencyProbe,[...portableImports,...messageIDs.map(name=>`static_assert(${name} > 0, "IPC message ID must be declared by fixture imports");`)].join('\n')+'\n');
 await writeFile(join(temp,'C01IPCQueues.inc'),section(socket,'// BEGIN C01 IPC owner queues.','// END C01 IPC owner queues.'));
 await writeFile(join(temp,'VPNIPCQueue.inc'),section(socket,'// BEGIN isolated VPN IPC sender.','static CFDataRef zx_sendVPNIPC('));
 await writeFile(join(temp,'VPNIPCSender.inc'),section(socket,'static CFDataRef zx_sendVPNIPC(','// END isolated VPN IPC sender.'));
 await writeFile(join(temp,'C01IPCReceiver.inc'),section(ipc,'// BEGIN C01 isolated IPC receiver.','// END C01 isolated IPC receiver.'));
 await writeFile(join(temp,'C01IPCHandler.inc'),section(ipc,'static CFDataRef handleIPCMessage(','void startIPCServer()'));
 await writeFile(join(temp,'C01IPCSenderActual.inc'),sender);
 const constants=daemonConstants
  .replaceAll('com.tlinkauto.tlinkautod.springboard',`test.${basename(temp)}.springboard`)
  .replace('/var/mobile/Library/TLinkauto/ipc_ready',join(temp,'ipc-ready'));
 await writeFile(join(temp,'C01IPCConstants.h'),constants);
 await writeFile(join(temp,'ipc-ready'),'ready');
 await writeFile(join(temp,'C01TaskEntry.inc'),entry);
 await writeFile(join(temp,'C01IPCSender.inc'),sender.replaceAll('access(','FixtureAccess(').replaceAll('CFMessagePortCreateRemote(','FixtureRemote(').replaceAll('CFMessagePortIsValid(','FixtureValid(').replaceAll('CFMessagePortSendRequest(','FixtureSend('));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'c01-ingress.exe':'c01-ingress'),file=join(root,'test/c01-ingress-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',`/FI${dependencyProbe}`,file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread','-include',dependencyProbe,file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'c01-ingress-runtime');
  run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/c01-ingress-runtime-test.mm'),join(root,'pccontrol/TLinkTaskContext.mm'),
   '-x','objective-c++',join(root,'pccontrol/SocketResponder.xm'),'-o',runtime]);run(runtime,[]);
  const isolated=join(temp,'c01-ipc-isolation');
  run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/c01-ipc-isolation-runtime-test.mm'),
   '-x','objective-c++',join(root,'pccontrol/SocketResponder.xm'),'-o',isolated]);run(isolated,[]);
 }else console.log('macOS actual root entry/sender and isolated two-port CF/run-loop fixture wired to CI; not run on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-c01-ingress-'));await rm(temp,{recursive:true,force:true});}
