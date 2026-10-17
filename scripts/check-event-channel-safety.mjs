import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async p => (await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [event, socket, troll, remote] = await Promise.all(['shared/TLinkEventChannel.mm','tlinkauto-binary/SocketServer.mm','stream-app/streamd/POCSocketServer.mm','stream-app/streamd/RemoteBridgeAgent.mm'].map(read));
function between(s,a,b) { const start = s.indexOf(a), end = s.indexOf(b,start+a.length); assert.ok(start >= 0 && end > start,a); return s.slice(start,end); }
assert.doesNotMatch(event,/usleep|NSRegularExpression/);
assert.match(event,/reader \? LOCK_SH : LOCK_EX/); assert.match(event,/operation \|= LOCK_NB/);
assert.ok(event.indexOf('notify_post(kTLinkEventNotification)') > event.indexOf('if (!persisted)'));
assert.match(event,/notify_register_dispatch/); assert.match(event,/TLinkEventMonotonicMs/);
assert.match(event,/DISPATCH_TIME_FOREVER/);
for (const source of [socket,troll]) {
 assert.match(source,/\[ctx.eventPollRequest cancel\]/);
 assert.match(source,/owner.eventPollRequest != request/);
}
assert.match(remote,/for \(TLinkEventPollRequest \*request in _eventPolls\) \[request cancel\]/);
assert.match(remote,/connection == owner->_controlTask/);
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot,'tlink-event-'));
function run(command,args) {
 const r = spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});
 if (r.stdout) process.stdout.write(r.stdout); if (r.stderr) process.stderr.write(r.stderr);
 if (r.error) throw r.error; assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);
}
try {
 const fixture = event.replace('@"/var/mobile/Library/TLinkauto/event-channel"',`@${JSON.stringify(join(temp,'journal'))}`).replace('notify_post(kTLinkEventNotification)', 'FixtureNotifyPost(kTLinkEventNotification)').replace('notify_register_dispatch(', 'FixtureRegisterNotification(');
 assert.notEqual(fixture,event);
 const fixtures = {
  'EventChannelUnderTest.inc': fixture,
  'EventConstantsUnderTest.inc': between(socket,'static const UInt8 kZXTPMagic','static std::atomic<uint64_t>'),
  'EventJSONUnderTest.inc': between(socket,'static NSDictionary *zx_jsonResponseFromLegacy(NSData *legacy, NSNumber *reqId)\n{','// BEGIN socket work adapter.'),
  'EventRootSocketUnderTest.inc': between(socket,'static NSData *zx_eventBatchResponse(', 'static dispatch_queue_t socketQueue()\n{'),
  'EventBodyUnderTest.inc': between(troll,'static NSString *TLinkBodyFromLine(', 'static NSArray<NSString *> *TLinkSplitBody('),
  'EventTrollSocketUnderTest.inc': between(troll,'// BEGIN TrollStore event socket adapter.', '// END TrollStore event socket adapter.'),
 };
 for (const [name,value] of Object.entries(fixtures)) await writeFile(join(temp,name),value);
 const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
 const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary = join(temp,windows ? 'event-core.exe' : 'event-core'), file = join(root,'test/event-channel-safety-test.cpp');
 run(compiler,msvc ? ['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
  : ['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
 run(binary,[]);
 if (process.platform === 'darwin') {
  const runtime = join(temp,'event-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fobjc-arc',
   '-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation',
   '-I',temp,'-I',join(root,'shared'),join(root,'test/event-channel-runtime-test.mm'),'-o',runtime]);
  run(runtime,[]);
 } else console.log('macOS actual journal/notification/async/cancellation and root/TrollStore/remote wire integration is wired to both workflows; not run on Windows.');
} finally { assert.equal(dirname(temp),tempRoot); assert.ok(basename(temp).startsWith('tlink-event-')); await rm(temp,{recursive:true,force:true}); }
