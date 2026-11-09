import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const consoleProducerSpecs=JSON.parse(readFileSync(new URL('./console-producer-specs.json',import.meta.url),'utf8'));
export function restoreConsoleProducer(source,kind){
    const spec=consoleProducerSpecs[kind];assert.ok(spec,kind);
    if(hash(source)===spec.beforeHash)return source;
    const marker=kind==='owner'?'    bool maySubmit() noexcept {':'TLinkJSConsolePrelude.h';
    if(!source.includes(marker))return source;
    assert.equal(hash(source),spec.currentHash,'complete console producer '+kind);
    for(const part of [...spec.parts].reverse()){assert.equal(source.split(part.current).length,2,part.name);source=source.replace(part.current,part.before);}
    assert.equal(hash(source),spec.beforeHash,'complete previous console/authority/runtime '+kind);return source;
}
