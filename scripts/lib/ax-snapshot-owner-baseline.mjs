import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXSnapshotOwner=readFileSync(new URL('../../test/fixtures/ax-snapshot-owner-before-c05l.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreAXSnapshotOwner(source){
    const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);
    const expected=legacyAXSnapshotOwner
        .replace('    CFTypeRef rawElements = NULL;\n','    CFTypeRef rawElements = NULL;\n    NSArray *elements = nil;\n')
        .replace('            if (rawElements) CFRelease(rawElements);\n','')
        .replace(`    } @catch (__unused NSException *exception) {
        if (root) CFRelease(root);
        if (rawElements) CFRelease(rawElements);
        return TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
    }

    NSArray *elements = CFBridgingRelease(rawElements);`,`        elements = CFBridgingRelease(rawElements);
        rawElements = NULL;
    } @catch (__unused NSException *exception) {
        return TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
    } @finally {
        if (root) CFRelease(root);
        if (rawElements) CFRelease(rawElements);
    }
`);
    assert.equal(source.slice(a,b),expected,'only snapshot acquisition owners/finally/ARC transfer; query/time/filter/count/metadata/authority source preserved');
    const restored=source.slice(0,a)+legacyAXSnapshotOwner+source.slice(b);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'65a98e514ab0a48f3b26d64ef64d66697445f858285edb47aa11b8dd3f040556',
        'complete preceding C05k attribute/hit-test/snapshot/selector/capability/foreground/action contract');
    return restored;
}
