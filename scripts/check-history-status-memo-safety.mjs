import {restoreHistoryStatusMemo,historyStatusMemoSpecs} from './lib/history-status-memo-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const source=await read(historyStatusMemoSpecs.file);restoreHistoryStatusMemo(source);
const part=name=>historyStatusMemoSpecs.parts.find(value=>value.name===name);
for(const name of ['reader','snapshot'])assert.equal(part(name).before,await read(`test/fixtures/history-status-${name}-before-c03bd.inc`));
assert.match(part('reader').current,/TLinkRunHistoryReadIndexData[\s\S]*TLinkHistoryStatusMemo::Lookup[\s\S]*JSONObjectWithData[\s\S]*containsObject:runId/);
assert.match(part('reader').current,/if\(status\)TLinkHistoryStatusMemo::Clear\(\)/);
const snapshot=part('snapshot').current;
assert.match(snapshot,/@finally[\s\S]*TLinkRunHistoryReleaseFileLock\(lockFd\)[\s\S]*stage = @"format"[\s\S]*if\(!memo.hit\)[\s\S]*TLinkHistoryStatusMemo::Offer/);
assert.match(snapshot,/@"persistence_diagnostics"[\s\S]*sTLinkRunHistoryPersistenceFailures/);
assert.match(snapshot,/TLinkHistoryStatusMemo::Clear\(\);\s*TLinkRunHistoryPersistenceFailure\(@"snapshot", stage, @"exception"\)/);
const module=await read('shared/TLinkHistoryStatusMemo.inc');
assert.doesNotMatch(module,/NSJSONSerialization|NSPropertyListSerialization|CFPropertyListCreateDeepCopy/);
assert.match(module,/limit!=read.limit[\s\S]*isEqualToData:data[\s\S]*CopyGraph\(value->rows,true/);
assert.match(module,/CopyGraph\(rows,false[\s\S]*\[data copy\]/);
assert.match(module,/retired.swap\(Stored\(\)\)[\s\S]*Stored\(\)=std::move\(value\);\}[\s\S]*retirement happens after/);
const runner=await read('scripts/check-run-history-safety.mjs'),fixture=await read('test/run-history-runtime-test.mm');
for(const dependency of ['HistoryStatusMemoUnderTest.inc','HistoryStatusSnapshotBefore.inc'])assert.ok(runner.includes(dependency)&&fixture.includes(dependency),dependency);
assert.match(fixture,/historyMemoEnabled=false/);assert.match(fixture,/historyStatusMemoCases\(\)/);
console.log('History status memo source passed: full preceding history reversal, fresh checked reads before lookup, unchanged validator/projector/writer/authority, independent mutable clones, fresh diagnostics and real native fixture seams.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-history-memo-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/history-projection-budget-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    console.log('Actual Foundation mutable/frozen projections, 129 fresh reads/one decode, failures, quotas and number/UTF16 pool ownership are included in the existing macOS history runtime; not executed on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-history-memo-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
