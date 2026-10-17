import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async p => (await readFile(join(root, p), 'utf8')).replaceAll('\r\n', '\n');
const [socket, ipc] = await Promise.all(['tlinkauto-binary/SocketServer.mm', 'pccontrol/IPCMessagePort.xm'].map(read));
function section(s, begin, end) { const a = s.indexOf(begin), b = s.indexOf(end, a + begin.length); assert.ok(a >= 0 && b > a, begin); return s.slice(a, b); }
assert.doesNotMatch(ipc, /CFWriteStreamCreateWithAllocatedBuffers|kCFStreamPropertyDataWritten|responseString|IPC task start:/);
assert.match(ipc, /TLinkIPCNoReplyTouch[\s\S]*processTaskWithContext\(\(UInt8 \*\)bytes \+ 6, \(size_t\)length - 6, NULL, nil\)/);
assert.ok(ipc.indexOf('TLinkIPCNoReplyTouch') < ipc.indexOf('NSString *command'));
assert.match(ipc, /ipc_response_too_large/);
assert.match(ipc, /static CFDataRef handleIPCMessage[\s\S]*@autoreleasepool/);
assert.match(socket, /DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM/);
assert.match(socket, /waitForResponse \? 1 : TLinkIPCNoReplyMessage/);
assert.doesNotMatch(socket, /CFWriteStreamWrite\(|IPC response: %s|task 10 dropped by rootfull license gate/);
const parser = section(socket, 'static void zx_processClientBuffer(ZXClientContext *ctx)\n{', 'static void handleDaemonMessage(');
assert.doesNotMatch(parser, /zx_handleLegacyRequestBytes\(|dispatch_sync\(ipcQueue/);
assert.match(parser, /ctx.requestPending/);
assert.match(socket, /send\(fd, bytes, length, MSG_DONTWAIT\)/);
assert.match(socket, /SO_NOSIGPIPE/);
assert.match(socket, /response_too_large/);
const fixtures = {
 'SocketContextUnderTest.inc': section(socket, 'typedef NS_ENUM', 'static const UInt8 kZXTPMagic'),
 'SocketConstantsUnderTest.inc': section(socket, 'static const UInt8 kZXTPMagic', 'static std::atomic<uint64_t>'),
 'SocketGlobalsUnderTest.inc': section(socket, 'static size_t gOutputBytes', 'static NSData *zx_eventChannelResponse'),
 'SocketPollUnderTest.inc': section(socket, 'static BOOL zx_deferLegacyEventPoll(', 'static dispatch_queue_t socketQueue()\n{'),
 'SocketQueueUnderTest.inc': section(socket, 'static dispatch_queue_t socketQueue()\n{', 'static void zx_cleanupClient'),
 'SocketCleanupUnderTest.inc': section(socket, 'static void zx_cleanupClient(CFReadStreamRef readStream)\n{', '#if TLINKAUTO_FILE_LOG'),
 'SocketOutputUnderTest.inc': section(socket, '// BEGIN socket output adapter.', '// END socket output adapter.'),
 'SocketWorkUnderTest.inc': section(socket, '// BEGIN socket work adapter.', '// END socket work adapter.'),
 'SocketJSONUnderTest.inc': section(socket, 'static NSDictionary *zx_jsonResponseFromLegacy(NSData *legacy, NSNumber *reqId)\n{', '// BEGIN socket work adapter.'),
 'SocketParserUnderTest.inc': parser,
 'SocketTaskTypeUnderTest.inc': section(socket, 'static int getTaskTypeFromBuffer(', 'static bool shouldRouteToSpringBoard('),
 'SocketReadUnderTest.inc': section(socket, 'static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo)\n{', 'static void TCPServerAcceptCallBack('),
 'SocketAcceptUnderTest.inc': socket.slice(socket.indexOf('static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)\n{')),
 'IPCHandlerUnderTest.inc': section(ipc, 'static CFDataRef handleIPCMessage(', 'void startIPCServer()'),
};
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot, 'tlink-socket-'));
function run(command, args) {
 const r = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 120000 });
 if (r.stdout) process.stdout.write(r.stdout); if (r.stderr) process.stderr.write(r.stderr);
 if (r.error) throw r.error; assert.equal(r.status, 0, `${command} failed (signal=${r.signal})`);
}
try {
 for (const [name, content] of Object.entries(fixtures)) await writeFile(join(temp, name), content);
 const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
 const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary = join(temp, windows ? 'socket-output.exe' : 'socket-output');
 const file = join(root, 'test/socket-output-safety-test.cpp');
 run(compiler, msvc ? ['/nologo', '/std:c++14', '/W4', '/WX', '/EHsc', file, `/Fe${binary}`, `/Fo${join(temp, 'core.obj')}`]
  : ['-std=c++11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', file, '-o', binary]);
 run(binary, []);
 if (process.platform === 'darwin') {
  const runtime = join(temp, 'socket-runtime');
  run(compiler, ['-std=c++11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-deprecated-declarations', '-fobjc-arc',
   '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-framework', 'Foundation', '-framework', 'CoreFoundation',
   '-I', temp, join(root, 'test/socket-transport-runtime-test.mm'), '-x', 'objective-c++', join(root, 'pccontrol/SocketResponder.xm'), '-o', runtime]);
  run(runtime, []);
 } else console.log('macOS actual socket parser/output/work/read/accept and CF IPC callback integration added to root CI; not run on this host.');
} finally { assert.equal(dirname(temp), tempRoot); assert.ok(basename(temp).startsWith('tlink-socket-')); await rm(temp, { recursive: true, force: true }); }
