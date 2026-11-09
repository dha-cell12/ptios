import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {join,dirname,basename,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {restoreConsoleProducer,consoleProducerSpecs} from './lib/console-producer-baseline.mjs';
import {checkConsoleProducerJS} from '../test/console-producer-js-test.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const texts=await Promise.all(['core','helper','owner'].map(async kind=>{const source=await read(consoleProducerSpecs[kind].file);restoreConsoleProducer(source,kind);return source;}));
const [core,helper,owner]=texts,prelude=await read('shared/TLinkJSConsolePrelude.h');
const decode=text=>(text.match(/@?"(?:\\.|[^"\\])*"/g)||[]).map(value=>JSON.parse(value.replace(/^@/,''))).join('');
const current=decode(prelude.slice(prelude.indexOf('return @"')));
const previous=await Promise.all(['core','helper'].map(async kind=>decode(await read(`test/fixtures/console-prelude-${kind}-before-c03ba.inc`))));
for(const [n,kind] of ['core','helper'].entries())assert.equal(consoleProducerSpecs[kind].parts.find(part=>part.name==='prelude').before,await read(`test/fixtures/console-prelude-${kind}-before-c03ba.inc`));
assert.match(current,/limit = 4097/);assert.doesNotMatch(current,/Array\.prototype\.map/);
assert.match(await read('shared/TLinkConsoleLogBudget.h'),/TLinkConsoleLogMessageUnits=4096;/);
assert.match(owner,/bool maySubmit\(\) noexcept[\s\S]*global_->snapshot\(\).pending>=TLinkConsoleLogMaxPending[\s\S]*budget_->dropped\(\)/);
assert.match(core,/const BOOL accepting=_acceptingLogs;[\s\S]*os_unfair_lock_unlock[\s\S]*if\(!accepting\)return NO/);
assert.match(helper,/return consoleOwner \? consoleOwner->maySubmit\(\) : YES/);
checkConsoleProducerJS(current,previous);
const part=(kind,name)=>consoleProducerSpecs[kind].parts.find(value=>value.name===name).current;
const gate=part('core','gate').replace(/- \(void\)beginConsoleLogging \{$/,'');
const coreHook=part('core','hook').replace('    context[@"_tlinkautoLoadBundleText"] =','');
const helperHook=part('helper','hook').replace('        ctx[@"_tlinkautoLoadBundleText"] =','');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-console-producer-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    await Promise.all([['ConsoleProducerGate.inc',gate],['ConsoleProducerCoreHook.inc',coreHook],['ConsoleProducerHelperHook.inc',helperHook],['ConsoleProducerOwner.inc',owner.replace('NSLog(','ProducerSystem(')]].map(([path,text])=>writeFile(join(temp,path),text)));
    if(process.platform==='darwin'){
        const binary=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/console-producer-runtime-test.mm'),'-o',binary]);run(binary,[temp]);
    }else console.log('macOS actual root/helper admission hooks, JSCore shared prelude and queued payload lifecycle included in CI; not executed here.');
    console.log('Console producer source passed: full preceding root/helper/owner reversal, unchanged backend/authority/termination bodies, shared prelude and native gate/hook extraction.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-console-producer-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
