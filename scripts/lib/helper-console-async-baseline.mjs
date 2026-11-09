import assert from 'node:assert/strict';
import {restoreConsoleProducer} from './console-producer-baseline.mjs';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const helperConsoleAsyncSpecs=JSON.parse(readFileSync(new URL('./helper-console-async-specs.json',import.meta.url),'utf8'));
export const helperConsoleAsyncBefore=readFileSync(new URL('../../test/fixtures/helper-console-metadata-before-c03az.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreHelperConsoleAsync(source){
    source=restoreConsoleProducer(source,'helper');
    if(!source.includes('#include "../shared/TLinkHelperConsoleAsync.inc"'))return source;
    const spec=helperConsoleAsyncSpecs;assert.equal(hash(source),spec.currentHash,'complete asynchronous helper logger source');
    for(const part of [...spec.parts].reverse()){assert.equal(source.split(part.current).length,2);source=source.replace(part.current,part.before);}
    assert.equal(hash(source),spec.beforeHash,'complete preceding helper/runtime/lifecycle/authority');return source;
}
export function restoreHelperConsoleMetadata(source){
    const spec=helperConsoleAsyncSpecs;assert.equal(hash(helperConsoleAsyncBefore),spec.moduleBeforeHash);
    if(source===helperConsoleAsyncBefore)return source;
    assert.equal(hash(source),spec.moduleCurrentHash,'complete metadata truncation accounting');return helperConsoleAsyncBefore;
}
