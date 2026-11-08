import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./persistence-json-storage-specs.json',import.meta.url),'utf8'));
export function persistenceJSONBeforeStorage(){
    const before=readFileSync(new URL('../../test/fixtures/persistence-json-before-c03as.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
    assert.equal(hash(before),spec.beforeHash,'complete preceding JSON stream');return before;
}
export function restorePersistenceJSONStorage(source){
    assert.equal(hash(source),spec.currentHash,'complete owned persistence stream');return persistenceJSONBeforeStorage();
}
export function checkPersistenceJSONStorage(core){assert.equal(hash(core),spec.coreHash,'complete bounded JSON storage core');}
