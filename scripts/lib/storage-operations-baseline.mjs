import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const storageOperationSpecs=JSON.parse(readFileSync(new URL('./storage-operations-specs.json',import.meta.url),'utf8'));
export const storageOperationBefore=part=>readFileSync(new URL('../../test/fixtures/'+part.frozen,import.meta.url),'utf8').replaceAll('\r\n','\n');
export function storageOperationPart(source,part){const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a);return source.slice(a,b);}
// Accept either complete known region so historical reversal chains can call
// this after a preceding stage has already restored the storage package.
export function restoreStorageOperations(source,kind,complete=false){
    const spec=storageOperationSpecs[kind];
    if(complete)assert.equal(hash(source),spec.currentHash,'complete C03ai '+kind);
    for(const part of spec.parts){
        const chunk=storageOperationPart(source,part),before=storageOperationBefore(part);
        if(chunk===before)continue;
        assert.equal(hash(chunk),part.currentHash,'complete C03ai storage '+kind+'/'+part.name);
        source=source.replace(chunk,before);
    }
    if(complete)assert.equal(hash(source),spec.oldHash,'complete preceding '+kind);
    return source;
}
