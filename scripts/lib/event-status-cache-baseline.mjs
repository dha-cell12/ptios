import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const eventStatusCacheSpecs=JSON.parse(readFileSync(new URL('./event-status-cache-specs.json',import.meta.url),'utf8'));
export function restoreEventStatusCache(source){
    if(!source.includes('TLinkEventStatusCache.h'))return source;
    const spec=eventStatusCacheSpecs;assert.equal(hash(source),spec.currentHash,'complete event status memo source');
    for(const part of [...spec.parts].reverse()){assert.equal(source.split(part.current).length,2,part.name);source=source.replace(part.current,part.before);}
    assert.equal(hash(source),spec.beforeHash,'complete preceding event reader/publisher/poll/authority');return source;
}
