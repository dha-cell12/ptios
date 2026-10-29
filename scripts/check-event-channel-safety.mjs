import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async p => (await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [event, socket, troll, remote] = await Promise.all(['shared/TLinkEventChannel.mm','tlinkauto-binary/SocketServer.mm','stream-app/streamd/POCSocketServer.mm','stream-app/streamd/RemoteBridgeAgent.mm'].map(read));
function between(s,a,b) { const start = s.indexOf(a), end = s.indexOf(b,start+a.length); assert.ok(start >= 0 && end > start,a); return s.slice(start,end); }
const oldReadOnlyReader = "static NSMutableDictionary *TLinkEventReadJournal(void)\n{\n    sTLinkEventJournalReads.fetch_add(1);\n    NSData *data = [NSData dataWithContentsOfFile:TLinkEventJournalPath()];\n    id object = data.length > 0\n        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]\n        : nil;\n    if ([object isKindOfClass:[NSDictionary class]] &&\n        [object[@\"events\"] isKindOfClass:[NSArray class]]) {\n        return [object mutableCopy];\n    }\n    return [@{\n        @\"schema\": TLinkEventChannelSchemaV1,\n        @\"next_sequence\": @1,\n        @\"events\": [NSMutableArray array],\n    } mutableCopy];\n}\n\n";
const oldLoader = "static NSDictionary *TLinkEventLoadSnapshot(BOOL nonBlocking, NSString **fingerprint) {\n    int fd = TLinkEventAcquireFileLock(YES, nonBlocking);\n    if (fd < 0) return nil;\n    NSDictionary *journal = nil;\n    @try {\n        journal = TLinkEventReadJournal();\n        if (fingerprint) *fingerprint = TLinkEventFileFingerprint();\n    } @finally { TLinkEventReleaseFileLock(fd); }\n    return journal;\n}\n";
const checkedLoader = between(event,'static NSDictionary *TLinkEventLoadSnapshot(','static void TLinkEventSweep(');
assert.match(checkedLoader,/TLinkEventReadJournal\(&readError\)/);
assert.match(checkedLoader,/@catch[\s\S]*event_journal_exception[\s\S]*@finally \{ TLinkEventReleaseFileLock\(fd\); \}/);
assert.doesNotMatch(checkedLoader,/WriteJournal|notify_post|unlink\(|removeItem/);
assert.ok(event.includes('else { sTLinkEventSnapshot = nil; sTLinkEventFingerprint = nil; }'));
assert.ok(event.includes('@"state": journal ? @"implemented" : @"error"'));
let beforeReads = event.replace(checkedLoader,oldLoader)
    .replace('static NSMutableDictionary *TLinkEventReadJournal(NSString **error)','static NSMutableDictionary *TLinkEventReadJournalForPublication(NSString **error)')
    .replace('NSMutableDictionary *journal = TLinkEventReadJournal(&readError);','NSMutableDictionary *journal = TLinkEventReadJournalForPublication(&readError);')
    .replace('// Checked reads must never replace',oldReadOnlyReader+'// Publication must never replace')
    .replace('    BOOL loaded = YES, changed = NO;\n    NSString *readError = nil;','    BOOL loaded = YES, changed = NO;')
    .replace('TLinkEventLoadSnapshot(YES, &fingerprint, &readError)','TLinkEventLoadSnapshot(YES, &fingerprint)')
    .replace('        else { sTLinkEventSnapshot = nil; sTLinkEventFingerprint = nil; }\n','');
const failedPoll = '            if (readError && ![readError isEqualToString:@"event_journal_unavailable"])\n                TLinkEventComplete(request, nil, readError);\n            else if (expired) TLinkEventComplete(request, nil, @"event_journal_unavailable");';
assert.ok(beforeReads.includes(failedPoll));
beforeReads = beforeReads.replace(failedPoll,'            if (expired) TLinkEventComplete(request, nil, @"event_journal_unavailable");');
const status = beforeReads.slice(beforeReads.indexOf('NSDictionary *TLinkEventChannelStatus(void)'));
const statusFailure = '    if (!journal) {\n        NSMutableDictionary *failed = [status mutableCopy];\n        failed[@"error"] = readError ?: @"event_journal_unavailable";\n        return [failed copy];\n    }\n    return status;\n';
assert.ok(status.includes(statusFailure));
const oldStatus = status.replace('    NSString *readError = nil;\n','')
    .replace('TLinkEventLoadSnapshot(NO, NULL, &readError)','TLinkEventLoadSnapshot(NO, NULL)')
    .replace('    NSDictionary *status = @{','    return @{')
    .replace('@"state": journal ? @"implemented" : @"error"','@"state": @"implemented"')
    .replace(statusFailure,'');
beforeReads = beforeReads.replace(status,oldStatus);
assert.equal(createHash('sha256').update(beforeReads.trim()).digest('hex'),'840748c9e52d871581b492b604225d32a1e3c767c67102c95951b3b3ab81fffa','reversing only shared checked reads, read-only failure/cache/status handling reproduces the complete user-passed C03n working source');
const publicationReader = between(beforeReads,'// Publication must never replace','static BOOL TLinkEventWriteJournal');
assert.match(publicationReader,/options:0 error:&readError/);
assert.match(publicationReader,/NSCocoaErrorDomain[\s\S]*NSFileReadNoSuchFileError[\s\S]*NSFileNoSuchFileError/);
assert.match(publicationReader,/CFBooleanGetTypeID/);
assert.match(publicationReader,/sequence < next[\s\S]*sequence == previous \+ 1/);
assert.match(publicationReader,/previous == next - 1/);
assert.doesNotMatch(publicationReader,/WriteJournal|notify_post|removeItem|unlink\(/);
let original = beforeReads.replace(publicationReader,'');
const publication = between(original,'        NSDictionary *event = nil;','        if (!persisted)');
assert.match(publication,/@finally \{ TLinkEventReleaseFileLock\(lockFd\); \}/);
assert.match(publication,/sequence == UINT64_MAX[\s\S]*event_journal_sequence_exhausted/);
let body = between(publication,'        @try { try {\n','        } catch (...)').slice('        @try { try {\n'.length);
body = body.split('\n').map(line=>line.startsWith('    ')?line.slice(4):line).join('\n');
body = body.replace('        NSString *readError = nil;\n        NSMutableDictionary *journal = TLinkEventReadJournalForPublication(&readError);\n        if (!journal) return @{@"state": @"error", @"error": readError};','        NSMutableDictionary *journal = TLinkEventReadJournal();')
    .replace('        uint64_t sequence = [journal[@"next_sequence"] unsignedLongLongValue];\n        if (sequence == UINT64_MAX) return @{@"state": @"error", @"error": @"event_journal_sequence_exhausted"};','        uint64_t sequence = MAX((uint64_t)1, [journal[@"next_sequence"] unsignedLongLongValue]);')
    .replace('        event = @{','        NSDictionary *event = @{')
    .replace('        persisted = TLinkEventWriteJournal(journal);','        BOOL persisted = TLinkEventWriteJournal(journal);');
original = original.replace(publication,body+'        TLinkEventReleaseFileLock(lockFd);\n');
assert.equal(createHash('sha256').update(original.trim()).digest('hex'),'254bf7e79bcf76974ae95a8a0f585e452686f934c7c82ecf7cefa1811be59a16','reversing only checked publish admission/overflow/unwind reproduces the complete 87aae836 event source; poll/status/success fields remain frozen');
assert.doesNotMatch(event,/usleep|NSRegularExpression/);
assert.match(event,/reader \? LOCK_SH : LOCK_EX/); assert.match(event,/operation \|= LOCK_NB/);
assert.ok(event.indexOf('notify_post(kTLinkEventNotification)') > event.indexOf('if (!persisted)'));
assert.match(event,/notify_register_dispatch/); assert.match(event,/TLinkEventMonotonicMs/);
assert.match(event,/DISPATCH_TIME_FOREVER/);
console.log('Event checked read/cache/status source passed; publication source passed: checked journal authority, sequence coherence/exhaustion, finally unlock and complete frozen success/poll/status source.');
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
 const fixture = event.replace('@"/var/mobile/Library/TLinkauto/event-channel"',`@${JSON.stringify(join(temp,'journal'))}`).replace('notify_post(kTLinkEventNotification)', 'FixtureNotifyPost(kTLinkEventNotification)').replace('notify_register_dispatch(', 'FixtureRegisterNotification(')
  .replace('[NSData dataWithContentsOfFile:TLinkEventJournalPath() options:0 error:&readError]','FixtureEventRead(TLinkEventJournalPath(), &readError)')
  .replace('![data writeToFile:path atomically:YES]','!FixtureEventWrite(data, path)')
  .replace('flock(fd, operation)', 'FixtureEventFlock(fd, operation)')
  .replace('flock(fd, LOCK_UN)', 'FixtureEventFlock(fd, LOCK_UN)')
  .replaceAll('close(fd)', 'FixtureEventClose(fd)');
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
