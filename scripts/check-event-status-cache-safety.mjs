import {restoreEventStatusCache,eventStatusCacheSpecs} from './lib/event-status-cache-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const source=await read(eventStatusCacheSpecs.file);restoreEventStatusCache(source);
const named=name=>eventStatusCacheSpecs.parts.find(part=>part.name===name);
for(const name of ['decode','status'])assert.equal(named(name).before,await read(`test/fixtures/event-status-${name}-before-c03bc.inc`));
const decode=named('decode'),at=decode.before.indexOf('    id object = [NSJSONSerialization');
const expected='static NSMutableDictionary *TLinkEventDecodeJournal(NSData *data, NSString **error)\n{\n'+decode.before.slice(at)+decode.before.slice(0,at)+'    return TLinkEventDecodeJournal(data,error);\n}\n\n';
assert.equal(decode.current,expected,'complete preceding JSON/schema/sequence/record validation is merely factored');
assert.match(named('status').current,/TLinkEventAcquireFileLock\(YES,NO\)[\s\S]*JournalReads.fetch_add\(1\)[\s\S]*TLinkEventReadJournalData[\s\S]*StatusMemo\(\).lookup[\s\S]*TLinkEventDecodeJournal[\s\S]*StatusMemo\(\).store/);
assert.match(named('status').current,/@finally \{if\(!succeeded\)TLinkEventStatusMemo\(\).clear\(\);TLinkEventReleaseFileLock\(fd\);\}/);
assert.doesNotMatch(source.slice(source.indexOf('NSDictionary *TLinkEventChannelStatus(void)')),/TLinkEventBatchFromJournal|@"events"/);
const runner=await read('scripts/check-event-channel-safety.mjs');
assert.match(runner,/replaceAll\('TLinkEventReadJournalData\(&missing, error\)'/);
assert.match(runner,/currentPreparationEvent=restoreEventStatusCache\(currentEvent\)/);
assert.match(runner,/EventStatusBefore.inc/);
console.log('Event status memo source passed: complete preceding source reversal, unchanged fresh-read/lock/publish/poll paths, identical factored validator, scalar status without batch construction and native dependency/fault seams.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-event-status-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/event-status-cache-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    console.log('Actual status/JSON/checked file/frozen reply and allocation-failure cases share the existing macOS Event runtime; Apple execution requires CI.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-event-status-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
