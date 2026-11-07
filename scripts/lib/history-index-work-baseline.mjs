import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./history-index-work-specs.json',import.meta.url),'utf8'));
export function restoreHistoryIndexWork(source){
    if(!source.includes('#include "TLinkHistoryRetirement.h"'))return source;
    assert.equal(hash(source),spec.currentHash,'complete C03aj history');
    source=source.replace('#include "TLinkHistoryRetirement.h"\n','');
    for(const part of spec.parts){
        const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a);
        const chunk=source.slice(a,b);assert.equal(hash(chunk),part.currentHash,part.name);
        const old=readFileSync(new URL('../../test/fixtures/history-index-'+part.name+'-before-c03aj.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
        source=source.slice(0,a)+old+source.slice(b);
    }
    assert.equal(hash(source),spec.beforeHash,'complete preceding C03ae history');return source;
}
