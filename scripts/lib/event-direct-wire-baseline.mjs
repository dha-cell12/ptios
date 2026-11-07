import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./event-direct-wire-specs.json',import.meta.url),'utf8'));
export function checkEventWireEncoding(source){assert.equal(hash(source),spec.coreHash,'complete checked event base64/frame encoder');}
export function restoreEventDirectWire(source){
    assert.equal(hash(source),spec.currentHash,'complete direct event wire/pool implementation');
    const before=readFileSync(new URL('../../test/fixtures/event-wire-before-c03ap.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
    assert.equal(hash(before),spec.beforeHash,'exact preceding Foundation event encoder');return before;
}
