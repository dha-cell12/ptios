import {restoreHelperConsole} from './helper-console-baseline.mjs';
import {restoreConsoleProducer} from './console-producer-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const consoleRetentionSpecs=JSON.parse(readFileSync(new URL('./console-retention-specs.json',import.meta.url),'utf8'));
export function restoreConsoleRetention(source,kind){
    source=restoreConsoleProducer(source,kind);
    if(kind==='helper')source=restoreHelperConsole(source);
    if(!source.includes('TLinkConsoleLogRetention.h'))return source;
    const spec=consoleRetentionSpecs[kind];assert.ok(spec,kind);
    assert.equal(hash(source),spec.currentHash,'complete terminal log retention '+kind);
    for(const text of spec.remove){assert.equal(source.split(text).length,2);source=source.replace(text,'');}
    assert.equal(hash(source),spec.beforeHash,'complete preceding logger/runtime/authority '+kind);return source;
}
