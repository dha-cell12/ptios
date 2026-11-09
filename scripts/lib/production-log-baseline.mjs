import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const productionLogSpecs=JSON.parse(readFileSync(new URL('./production-log-specs.json',import.meta.url),'utf8'));
export function restoreProductionLog(source,kind='server'){
    const spec=productionLogSpecs.files[kind];
    const marker=kind==='server'?'#include "TLinkScriptLogBuffer.inc"':kind==='injector'?'#include "TLinkProductionLog.inc"':'// BEGIN bounded production log API.';
    if(!source.includes(marker))return source;
    assert.equal(hash(source),spec.currentHash,'complete bounded production log '+kind);
    for(const part of [...spec.parts].reverse()){
        assert.equal(source.split(part.current).length,2,part.name);source=source.replace(part.current,part.before);
    }
    assert.equal(hash(source),spec.beforeHash,'complete preceding production '+kind);return source;
}
export function checkProductionLogHelpers(){
    for(const [path,expected] of Object.entries(productionLogSpecs.helpers)){
        assert.equal(hash(readFileSync(new URL('../../'+path,import.meta.url),'utf8').replaceAll('\r\n','\n')),expected,path);
    }
}
