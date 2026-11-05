import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXAdmission} from './ax-admission-baseline.mjs';
export const legacyAXQueryStop=readFileSync(new URL('../../test/fixtures/ax-query-stop-before-c05m.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axQueryRegion(source){const a=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t'),b=source.indexOf('BOOL TLinkAXResultCompleteForAction(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXQueryStop(source){
    source=restoreAXAdmission(source);
    const gate='    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});\n';
    const expected=legacyAXQueryStop
        .replace('NSDictionary *TLinkAXCopySnapshot(pid_t pid, NSString *bundleID, NSDictionary *options)\n{\n',
            'NSDictionary *TLinkAXCopySnapshot(pid_t pid, NSString *bundleID, NSDictionary *options)\n{\n'+gate)
        .replace('    if (!TLinkAXResultSucceeded(snapshot)) return snapshot;\n','    if (!TLinkAXResultSucceeded(snapshot)) return snapshot;\n'+gate)
        .replace('    NSDictionary *element = selectedElement;\n',gate+'    NSDictionary *element = selectedElement;\n')
        .replace('    NSMutableDictionary *options = [NSMutableDictionary dictionary];\n',gate+'    NSMutableDictionary *options = [NSMutableDictionary dictionary];\n')
        .replaceAll('    });\n    return result ?: TLinkAXError(','    });\n'+gate+'    return result ?: TLinkAXError(');
    assert.equal(axQueryRegion(source),expected,'only six caller-stop gates; snapshot/query dispatch, selector validation, matcher/count/index/fields/authority source preserved');
    const restored=source.replace(axQueryRegion(source),legacyAXQueryStop);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'b511a33322eff8d9b30b14f58731b0276f477c9ff729e90a6fcba2770bc44ad0',
        'complete preceding C05l snapshot owners/attribute/hit-test/capability/foreground/action source');
    return restored;
}
