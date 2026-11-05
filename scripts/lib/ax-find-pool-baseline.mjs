import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXFindPool=readFileSync(new URL('../../test/fixtures/ax-find-pool-before-c05o.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreAXFindPool(source){
    const a=source.indexOf('static NSDictionary *TLinkAXFindInSnapshot('),b=source.indexOf('NSDictionary *TLinkAXFindElement(',a);assert.ok(a>=0&&b>a);
    const start=legacyAXFindPool.indexOf('        if (visibleOnly &&'),end=legacyAXFindPool.indexOf('    }\n    if (TLinkNativeStopped())',start);assert.ok(start>0&&end>start);
    const body=legacyAXFindPool.slice(start,end).split('\n').map(line=>line?'    '+line:line).join('\n');
    const expected=legacyAXFindPool.slice(0,start)+'        @autoreleasepool {\n'+body+'        }\n'+legacyAXFindPool.slice(end);
    assert.equal(source.slice(a,b),expected,'only per-row pool/indentation; admission, normalization, predicates/count/index/cancel/result source preserved');
    const restored=source.slice(0,a)+legacyAXFindPool+source.slice(b);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'da7ebdcd9c416fbcd7c37cc4349284046169af6892c2321fadd8cbc7e8800623',
        'complete preceding C05n admission/capability/snapshot/attribute/hit-test/foreground/authority source');
    return restored;
}
