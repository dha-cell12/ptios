import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXNodePool=readFileSync(new URL('../../test/fixtures/ax-snapshot-before-c05f.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axNodePoolSnapshot(source){const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXNodePool(source){
    const a=legacyAXNodePool.indexOf('        scanned++;'),b=legacyAXNodePool.indexOf('    }\n    if (TLinkNativeStopped()) return TLinkAXError',a);
    assert.ok(a>=0&&b>a);
    const body=legacyAXNodePool.slice(a,b).split('\n').map(line=>line?'    '+line:line).join('\n');
    const expected=legacyAXNodePool.slice(0,a)+'        @autoreleasepool {\n'+body+'        }\n'+legacyAXNodePool.slice(b);
    assert.equal(axNodePoolSnapshot(source),expected,'only per-node pool/indentation; all admission, filters, output, CF, timing and result source preserved');
    const restored=source.replace(axNodePoolSnapshot(source),legacyAXNodePool);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'db17ba6dd4795419d8ca9549d986856216fcd2aa00884554d152948ae4409dd9',
        'complete preceding C05e AX snapshot/matcher/foreground/action/authority contract');
    return restored;
}
