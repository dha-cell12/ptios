import {restoreDiagnosticsBatch} from './license-diagnostics-batch-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyUISnapshot=readFileSync(new URL('../../test/fixtures/license-ui-before-c06ab.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function uiSnapshotMethod(source){const a=source.indexOf('- (void)refreshLicenseUISnapshotAsyncForReason:'),b=source.indexOf('- (void)updateDiagnostics:',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreUISnapshot(source){
    source=restoreDiagnosticsBatch(source);
    const restored=source.replace(uiSnapshotMethod(source),legacyUISnapshot);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'4883be12e0199ffc81274437261258202feff054462b32d2526e9e59d16f2257',
        'complete preceding coordinator authority/HTTP/refresh/reload/diagnostics/subscription source');
    return restored;
}
