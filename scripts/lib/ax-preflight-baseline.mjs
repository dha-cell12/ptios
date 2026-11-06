import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXOutput} from './ax-output-baseline.mjs';
export const legacyAXPreflight=readFileSync(new URL('../../test/fixtures/ax-preflight-before-c05p.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreAXPreflight(source){
    source=restoreAXOutput(source);
    const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);
    const early='    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", nil);\n';
    const late='if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});\n';
    const expected=legacyAXPreflight
        .replace('    NSDictionary *lockState = TLinkAXLockState();\n',early+'    NSDictionary *lockState = TLinkAXLockState();\n'+early)
        .replace('    if (!TLinkAXPrepare()) return TLinkAXError(@"ui_axruntime_unavailable", @{@"pid": @(pid)});',
            '    BOOL prepared = TLinkAXPrepare();\n'+early+'    if (!prepared) return TLinkAXError(@"ui_axruntime_unavailable", @{@"pid": @(pid)});')
        .replace('    @try {\n        root = sTLinkAXCreateApp(pid);','    @try {\n    '+early+'        root = sTLinkAXCreateApp(pid);')
        .replace('        elements = CFBridgingRelease(rawElements);','        '+late+'        elements = CFBridgingRelease(rawElements);')
        .replace('    CGRect screen = [UIScreen mainScreen].bounds;\n','    CGRect screen = [UIScreen mainScreen].bounds;\n    '+late);
    assert.equal(source.slice(a,b),expected,'only caller-stop preflight/post-query/screen gates; PID/query-error priority, owner transfer, local timing/rows/fields/authority preserved');
    const restored=source.slice(0,a)+legacyAXPreflight+source.slice(b);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'e25a80d31a9af47aec2156f86fef6bb5473754591b26da648879bf20c916d382',
        'complete preceding C05o pools/admission/attributes/hit-test/capability/foreground/action source');
    return restored;
}
