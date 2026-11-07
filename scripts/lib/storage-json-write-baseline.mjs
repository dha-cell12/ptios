import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
export const storageJSONWriteSpecs=JSON.parse(readFileSync(new URL('./storage-json-write-specs.json',import.meta.url),'utf8'));
export const storageJSONWriteBefore=kind=>readFileSync(new URL('../../test/fixtures/storage-json-write-'+kind+'-before-c03an.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function checkPreparedJSONText(source){assert.equal(hash(source),storageJSONWriteSpecs.adapterHash,'complete immutable prepared JSON string/bytes adapter');}
export function restoreStorageJSONWrites(source,kind){
    const spec=storageJSONWriteSpecs[kind];
    if(!spec||!source.includes(spec.include))return source;
    assert.equal(hash(source),spec.currentHash,'complete prepared JSON '+kind);
    const a=source.indexOf(spec.start),b=source.indexOf(spec.end,a+spec.start.length);assert.ok(a>=0&&b>a);
    assert.equal(hash(source.slice(a,b)),spec.partHash,'complete prepared JSON route '+kind);
    source=(source.slice(0,a)+storageJSONWriteBefore(kind)+source.slice(b)).replace(spec.include,'');
    assert.equal(hash(source),spec.beforeHash,'complete preceding storage/authority source '+kind);return source;
}
