import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
export const fileReadStorageSpecs=JSON.parse(readFileSync(new URL('./file-read-storage-specs.json',import.meta.url),'utf8'));
const frozen=name=>readFileSync(new URL('../../test/fixtures/file-read-storage-'+name+'before-c03au.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function checkFileReadStorageCore(source){assert.equal(hash(source),fileReadStorageSpecs.coreHash,'complete raw read storage policy');}
export function restoreFileReadStorage(source){
    const spec=fileReadStorageSpecs;
    if(!source.includes(spec.include))return source;
    assert.equal(hash(source),spec.currentHash,'complete direct raw FileHandle implementation');
    assert.equal(source.split(spec.helper).length,2,'one shared storage/data owner helper');
    source=source.replace(spec.include,'').replace(spec.helper,'');
    for(const part of spec.parts){
        assert.equal(source.split(part.current).length,2,'one complete raw '+part.name+' reader');
        source=source.replace(part.current,frozen(part.name+'-'));
    }
    assert.equal(source,frozen(''),'complete preceding class, all IO/codec/frontend policy retained');
    assert.equal(hash(source),spec.beforeHash);return source;
}
