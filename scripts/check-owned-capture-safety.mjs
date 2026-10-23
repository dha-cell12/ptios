import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [screen,header,socket,ipc]=await Promise.all(['pccontrol/Screen.xm','pccontrol/Screen.h','tlinkauto-binary/SocketServer.mm','pccontrol/IPCMessagePort.xm'].map(read));
function section(text,a,b){const start=text.indexOf(a),end=text.indexOf(b,start+a.length);assert.ok(start>=0&&end>start,a);return text.slice(start,end);}
const task21=section(socket,'static char *handleTemplateMatchTaskInDaemon(const char *buffer)\n{','\n#endif');
assert.ok(task21.indexOf('TLinkCaptureClientLease')<task21.indexOf('zx_ipcCaptureScreenshotToPath('));
assert.match(task21,/@finally \{captureLease.cancel\(\);\}/);assert.doesNotMatch(socket,/zx_safeUnlink/);
assert.match(socket,/owned_capture_reply_path_mismatch/);assert.match(ipc,/ownedCapture->finish\(\)/);
const writer=section(screen,'// BEGIN owned screenshot write adapter.','// END owned screenshot write adapter.');
const method=section(screen,'+ (NSString*)screenShotToPath:','+ (PHAssetCollection');
assert.match(method,/!owned && shouldReuseKeep/);assert.ok(method.indexOf('if(owned)return zx_writeOwnedCapture')<method.indexOf('NSString *parentDir'));
assert.ok(method.indexOf('zx_ownedCaptureContinue(error)')<method.indexOf('CGSize imageSize'));
assert.ok(method.lastIndexOf('zx_ownedCaptureContinue(error)')<method.indexOf('UIImageJPEGRepresentation'));
assert.match(method,/@finally \{CGImageRelease\(outputRef\);\}/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-owned-capture-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 const fixtures={
  'OwnedIPCQueues.inc':section(socket,'// BEGIN C01 IPC owner queues.','// END C01 IPC owner queues.'),
  'OwnedWriter.inc':writer,
  'OwnedScreenshotHandler.inc':section(screen,'NSString* handleScreenshotTaskFromRawData(','void handleScreenKeepTaskFromRawData('),
  'OwnedScreenshotConstants.h':[...header.matchAll(/^#define SCREENSHOT_TASK_[^\n]+/gm)].map(match=>match[0]).join('\n'),
  'OwnedIPCHandler.inc':section(ipc,'static CFDataRef handleIPCMessage(','void startIPCServer()'),
  'OwnedDaemonHelper.inc':section(socket,'static char *zx_strdup_nsstring(','static int zx_ipcGetFrontmostOrientation('),
  'OwnedDaemonPath.inc':section(socket,'static NSString *zx_makeTempScreenshotPath(','#ifdef ZX_DAEMON'),
  'OwnedDaemonTask.inc':task21,
 };
 for(const [name,body] of Object.entries(fixtures))await writeFile(join(temp,name),body);
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'capture-lease.exe':'capture-lease'),file=join(root,'test/capture-lease-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'owned-capture-runtime');
  run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-framework','ImageIO','-I',temp,
   join(root,'test/capture-lease-runtime-test.mm'),'-x','objective-c++',join(root,'pccontrol/SocketResponder.xm'),'-o',runtime]);run(runtime,[]);
 }else console.log('macOS actual daemon/CF callback/screenshot adapter with real PNG/POSIX lease tests wired to CI; not run on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-owned-capture-'));await rm(temp,{recursive:true,force:true});}
