import {restorePersistenceJSON} from './persistence-json-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./event-preparation-specs.json',import.meta.url),'utf8'));
export function checkEventPreparationFiles(core,counter){
    assert.equal(hash(core),spec.coreHash,'complete event search/count core');
    assert.equal(hash(counter),spec.counterHash,'complete private JSON counter/lifecycle');
}
export const eventPreparationBefore=name=>readFileSync(new URL('../../test/fixtures/event-preparation-'+name+'-before-c03ak.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreEventPreparation(source){
    source=restorePersistenceJSON(source,'event');
    if(!source.includes('#include "TLinkEventPreparation.h"'))return source;
    assert.equal(hash(source),spec.currentHash,'complete C03ak event source');
    source=source.replace('#include "TLinkEventPreparation.h"\n','').replace('#include "TLinkEventJSONCounter.inc"\n\n','');
    for(const part of spec.parts){
        const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a);
        assert.equal(hash(source.slice(a,b)),part.currentHash,part.name);
        source=source.slice(0,a)+eventPreparationBefore(part.name)+source.slice(b);
    }
    assert.equal(hash(source),spec.beforeHash,'complete preceding C03af event source');return source;
}
