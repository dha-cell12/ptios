import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const historyStatusMemoSpecs=JSON.parse(readFileSync(new URL('./history-status-memo-specs.json',import.meta.url),'utf8'));
export function restoreHistoryStatusMemo(source){
    if(!source.includes('TLinkHistoryStatusMemo.inc'))return source;
    const spec=historyStatusMemoSpecs;assert.equal(hash(source),spec.currentHash,'complete history projection memo source');
    for(const part of [...spec.parts].reverse()){assert.equal(source.split(part.current).length,2,part.name);source=source.replace(part.current,part.before);}
    assert.equal(hash(source),spec.beforeHash,'complete preceding history transaction/authority/status source');return source;
}
