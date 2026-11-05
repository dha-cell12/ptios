import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXParentAttributes} from './ax-parent-attributes-baseline.mjs';
export const legacyAXHitTest=readFileSync(new URL('../../test/fixtures/ax-hit-test-before-c05j.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axHitTest(source){const a=source.indexOf('NSDictionary *TLinkAXElementAtPoint(');assert.ok(a>=0);return source.slice(a);}
export function restoreAXHitTest(source){
    source=restoreAXParentAttributes(source);
    const cancel='if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});\n';
    const stop=indent=>`${indent}if (TLinkNativeStopped()) {
${indent}    result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
${indent}    return;
${indent}}
`;
    const expected=legacyAXHitTest
        .replace('    __block NSDictionary *result = nil;','    '+cancel+'    __block NSDictionary *result = nil;')
        .replace('        NSDictionary *lockState = TLinkAXLockState();\n','        NSDictionary *lockState = TLinkAXLockState();\n'+stop('        '))
        .replace('        if (!TLinkAXPrepare() || !sTLinkAXHitTest) {','        BOOL prepared = TLinkAXPrepare();\n'+stop('        ')+'        if (!prepared || !sTLinkAXHitTest) {')
        .replace('        @try {\n            root = sTLinkAXCreateApp(pid);\n','        @try {\n'+stop('            ')+'            root = sTLinkAXCreateApp(pid);\n'+stop('            '))
        .replace('            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, 0.5f);',`            auto budget = TLinkCurrentNativeBudget();
            double timeout = budget ? budget->remainingSeconds(0.5) : 0.5;
            if (timeout <= 0 || TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, (float)timeout);
`+stop('            ').trimEnd())
        .replace('            root = NULL;\n','            root = NULL;\n'+stop('            '))
        .replace('                if (hit) CFRelease(hit);\n','')
        .replace('            hit = NULL;\n','            hit = NULL;\n'+stop('            '))
        .replace(`        } @catch (__unused NSException *exception) {
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        }`,`        } @catch (__unused NSException *exception) {
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        } @finally {
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
        }`)
        .replace('    });\n','    });\n    '+cancel);
    assert.equal(axHitTest(source),expected,'only caller stop/root timeout gates and finally ownership; hit fields, invalid/lock/symbol/geometry/NS-error/provider policy preserved');
    const restored=source.replace(axHitTest(source),legacyAXHitTest);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'d610a6fdfdfd0fb857881d597f2d4b8034aadf2621304943595ae9775c2ee5ca',
        'complete preceding C05i AX capability/foreground/snapshot/selector/authority/action source');
    return restored;
}
