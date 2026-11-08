import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const spec=JSON.parse(readFileSync(new URL('./history-recovery-codec-specs.json',import.meta.url),'utf8'));
export function checkHistoryRecoveryCompare(source){assert.equal(hash(source),spec.coreHash,'complete lazy recovery compare core');}
export function restoreHistoryRecoveryCodec(source){
    if(!source.includes('#include "TLinkHistoryRecoveryCompare.h"'))return source;
    assert.equal(hash(source),spec.currentHash,'complete C03ar history');
    source=source.replace('#include "TLinkHistoryRecoveryCompare.h"\n','');
    for(const part of spec.parts){
        const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a);
        assert.equal(hash(source.slice(a,b)),part.currentHash,part.name);
        const before=readFileSync(new URL('../../test/fixtures/history-recovery-'+part.name+'-before-c03ar.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
        source=source.slice(0,a)+before+source.slice(b);
    }
    assert.equal(hash(source),spec.beforeHash,'complete user-passed C03aq history');return source;
}
