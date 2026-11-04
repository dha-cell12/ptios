import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXSnapshot=readFileSync(new URL('../../test/fixtures/ax-snapshot-before-c05b.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axSnapshot(source){const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXSnapshot(source){
    const expected=legacyAXSnapshot
        .replace('    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();\n    CFAbsoluteTime deadline = started + ((double)timeoutMs / 1000.0);','    TLinkAXSnapshotWindow window(TLinkNativeNowNs(), (unsigned)timeoutMs);')
        .replace('        if (TLinkNativeStopped()) { CFRelease(root);','        queryTimeout = window.remainingSeconds(TLinkNativeNowNs(), queryTimeout);\n        if (TLinkNativeStopped() || queryTimeout <= 0) { CFRelease(root);')
        .replace('CFAbsoluteTimeGetCurrent() >= deadline','window.remainingSeconds(TLinkNativeNowNs(), 1.0) <= 0')
        .replace('        if (!node) {','        if (window.remainingSeconds(TLinkNativeNowNs(), 1.0) <= 0) {\n            truncated = YES;\n            break;\n        }\n        if (!node) {')
        .replace('    NSTimeInterval durationMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;',`    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    const uint64_t finished = TLinkNativeNowNs();
    if (window.remainingSeconds(finished, 1.0) <= 0) truncated = YES;
    NSTimeInterval durationMs = window.elapsedMilliseconds(finished);`);
    assert.equal(axSnapshot(source),expected,'only snapshot clock/query remainder/late-completeness changes; complete provider/filter/output/result source');
    const restored=source.replace('#include "TLinkAXSnapshotWindow.h"\n','').replace(axSnapshot(source),legacyAXSnapshot);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'1dda2d202f261bc56651cb80867946de81fe18bd2d6018819a76988d5bd0f76d',
        'complete preceding AX source, symbol caches, serializer, selector, foreground/tap and task contract');
    return restored;
}
