import assert from 'node:assert/strict';
import {restoreEventStatusCache} from './event-status-cache-baseline.mjs';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8').replaceAll('\r\n','\n');
const spec=JSON.parse(readFileSync(new URL('./owned-read-buffer-specs.json',import.meta.url),'utf8'));
export function restoreOwnedReadFile(source,kind){
    const part=spec.files[kind];assert.equal(hash(source),part.currentHash,'complete C03at '+kind);
    const before=read('test/fixtures/owned-read-'+kind+'-before-c03at.inc');
    assert.equal(hash(before),part.beforeHash,'complete preceding '+kind);
    let restored=source;
    if(kind==='module'){
        const marker='\n// BEGIN owned file read buffer.';assert.equal(restored.split(marker).length-1,1);
        restored=restored.slice(0,restored.indexOf(marker)).replace('#import "TLinkOwnedReadBuffer.h"\n','');
    }else{
        const a=restored.indexOf('    // Reserve storage without initializing it;'),b=restored.indexOf('    bool seal(){',a);
        assert.ok(a>=0&&b>a);restored=restored.slice(0,a)+restored.slice(b);
    }
    assert.equal(restored,before,'only read reservation/publication additions change '+kind);return restored;
}
export function checkOwnedReadHeader(){assert.equal(hash(read('shared/TLinkOwnedReadBuffer.h')),spec.headerHash,'complete committed read-buffer interface');}
export function ownedReadBefore(kind,name){return read('test/fixtures/owned-read-'+kind+'-'+name+'-before-c03at.inc');}
export function restoreOwnedReadSource(source,kind){
    if(kind==='event')source=restoreEventStatusCache(source);
    if(!source.includes('#include "TLinkOwnedReadBuffer.h"'))return source;
    const part=spec.sources[kind];assert.equal(hash(source),part.currentHash,'complete C03at '+kind);
    source=source.replace('#include "TLinkOwnedReadBuffer.h"\n','');
    for(const region of part.parts){
        const a=source.indexOf(region.start),b=source.indexOf(region.end,a+region.start.length);assert.ok(a>=0&&b>a);
        assert.equal(hash(source.slice(a,b)),region.currentHash,kind+' '+region.name);
        source=source.slice(0,a)+ownedReadBefore(kind,region.name)+source.slice(b);
    }
    assert.equal(hash(source),part.beforeHash,'complete preceding '+kind+' IO/authority source');return source;
}
