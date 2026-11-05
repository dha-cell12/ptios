import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXParentAttributes=readFileSync(new URL('../../test/fixtures/ax-parent-attributes-before-c05k.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
function attributes(source){const a=source.indexOf('static id TLinkAXAttribute('),b=source.indexOf('static NSInteger TLinkAXBoundedInteger(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXParentAttributes(source){
    const expected=legacyAXParentAttributes
        .replace('    if (window) {\n        auto budget = TLinkCurrentNativeBudget();','    auto budget = TLinkCurrentNativeBudget();\n    if (window || budget) {')
        .replace('        timeout = window->remainingSeconds(TLinkNativeNowNs(), timeout);','        if (window) timeout = window->remainingSeconds(TLinkNativeNowNs(), timeout);')
        .replace('        if (timeout <= 0) return nil;','        if (timeout <= 0 || TLinkNativeStopped()) return nil;')
        .replace('        if (TLinkNativeStopped() || window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0) return nil;',
            '        if (TLinkNativeStopped() || (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)) return nil;')
        .replace(`        if (error != 0 || (window && (TLinkNativeStopped() ||
            window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0))) return nil;`,`        if (error != 0 || ((window || budget) && (TLinkNativeStopped() ||
            (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)))) return nil;`)
        .replace('        if (!window && sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, nativeBudget ? (float)nativeBudget->remainingSeconds(0.10) : 0.10f);',
            '        if (!window && !nativeBudget && sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, 0.10f);')
        .replace(`        if (window && (TLinkNativeStopped() ||
            window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)) return nil;`,`        if ((window || nativeBudget) && (TLinkNativeStopped() ||
            (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0))) return nil;`);
    assert.equal(attributes(source),expected,'only per-attribute parent timeout/pre-post gates and serializer final gate; CF/geometry/fields/local-window behavior preserved');
    const restored=source.replace(attributes(source),legacyAXParentAttributes);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'4d52bb2972707d388a93ef1a13c9755f9b31b63611a9d7da0f79ceb967d09c77',
        'complete preceding C05j hit-test/snapshot/selector/capability/foreground/action/authority source');
    return restored;
}
