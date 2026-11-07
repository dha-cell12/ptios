import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./helper-replay-owner-specs.json',import.meta.url),'utf8'));
export function helperReplayBefore(source){
    assert.equal(hash(source),spec.currentHash,'complete retained replay payload/identity dispatcher');
    const before=readFileSync(new URL('../../test/fixtures/helper-replay-before-c02c4.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
    assert.equal(hash(before),spec.beforeHash,'complete preceding replay core/dispatcher');return before;
}
