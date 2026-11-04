import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXFind} from './ax-find-baseline.mjs';
export const legacyAXScan=readFileSync(new URL('../../test/fixtures/ax-snapshot-before-c05d.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export const axScanLimits=`// Scanned nodes are bounded independently of rows surviving the filters.
static const NSInteger kTLinkAXDefaultMaxScannedElements = 4096;
static const NSInteger kTLinkAXHardMaxScannedElements = 16384;
`;
function snapshot(source){const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXScan(source){
    source=restoreAXFind(source);
    const expected=legacyAXScan
        .replace('    id maxElementsValue = options[@"max_elements"] ?: options[@"maxElements"];',`    id maxElementsValue = options[@"max_elements"] ?: options[@"maxElements"];
    id maxScannedValue = options[@"max_scanned_elements"] ?: options[@"maxScannedElements"];`)
        .replace('    NSInteger maxElements = TLinkAXBoundedInteger(maxElementsValue, 250, 1, 1000);',`    NSInteger maxElements = TLinkAXBoundedInteger(maxElementsValue, 250, 1, 1000);
    NSInteger maxScannedElements = TLinkAXBoundedInteger(maxScannedValue,
        kTLinkAXDefaultMaxScannedElements, 1, kTLinkAXHardMaxScannedElements);`)
        .replace('rows.count >= (NSUInteger)maxElements || window.remainingSeconds','rows.count >= (NSUInteger)maxElements || scanned >= (NSUInteger)maxScannedElements ||\n            window.remainingSeconds');
    assert.equal(snapshot(source),expected,'only independent scanned-node normalization/loop admission; all row/filter/deadline/output/result fields preserved');
    const capabilities=`        @"default_max_scanned_elements": @(kTLinkAXDefaultMaxScannedElements),
        @"hard_max_scanned_elements": @(kTLinkAXHardMaxScannedElements),
`;
    const forward='    options[@"max_scanned_elements"] = selector[@"max_scanned_elements"] ?: selector[@"maxScannedElements"] ?: @(kTLinkAXDefaultMaxScannedElements);\n';
    for(const added of [axScanLimits,capabilities,forward])assert.ok(source.includes(added));
    const restored=source.replace(snapshot(source),legacyAXScan).replace('\n'+axScanLimits,'').replace(capabilities,'').replace(forward,'');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'e9c10c37e3de5752ea53cc895a99c77e88f72f171943be0333d8f700d50483be',
        'complete preceding C05c AX, serializer/CF/symbol/selector/foreground/action and task contract');
    return restored;
}
