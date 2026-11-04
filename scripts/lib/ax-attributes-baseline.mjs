import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXAttributes=readFileSync(new URL('../../test/fixtures/ax-attributes-before-c05c.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axAttributes(source){const a=source.indexOf('static id TLinkAXAttribute('),b=source.indexOf('static NSInteger TLinkAXBoundedInteger(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXAttributes(source){
    const attribute=`static id TLinkAXAttribute(TLinkAXElementRef element, uint32_t key, int *errorOut,
                         TLinkAXSnapshotWindow *window = nullptr)
{
    if (TLinkNativeStopped()) return nil;
    if (!element || !sTLinkAXCopyAttribute) return nil;
    if (window) {
        auto budget = TLinkCurrentNativeBudget();
        double timeout = budget ? budget->remainingSeconds(0.10) : 0.10;
        timeout = window->remainingSeconds(TLinkNativeNowNs(), timeout);
        if (timeout <= 0) return nil;
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, (float)timeout);
        if (TLinkNativeStopped() || window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0) return nil;
    }
    CFTypeRef value = NULL;
    @try {
        int error = sTLinkAXCopyAttribute(element, (CFStringRef)(uintptr_t)key, &value);
        if (errorOut) *errorOut = error;
        if (error != 0 || (window && (TLinkNativeStopped() ||
            window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0))) return nil;
        id result = value ? CFBridgingRelease(value) : nil;
        value = NULL;
        return result;
    } @finally {
        if (value) CFRelease(value);
    }
}

`;
    const beforeAttribute=legacyAXAttributes.slice(0,legacyAXAttributes.indexOf('static NSString *TLinkAXStringValue('));
    const expected=legacyAXAttributes.replace(beforeAttribute,attribute)
        .replace('                                             NSUInteger index)','                                             NSUInteger index,\n                                             TLinkAXSnapshotWindow *window = nullptr)')
        .replace('if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, nativeBudget','if (!window && sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, nativeBudget')
        .replaceAll(/TLinkAXAttribute\(element, (\d+), NULL\)/g,'TLinkAXAttribute(element, $1, NULL, window)')
        .replace('        return @{\n            @"index":',`        if (window && (TLinkNativeStopped() ||
            window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)) return nil;
        return @{
            @"index":`);
    assert.equal(axAttributes(source),expected,'only scoped per-attribute timeout/stop/CF owner changes; complete geometry/traits/string/activation/row logic retained');
    const rootGuard=`        if (TLinkNativeStopped() || window.remainingSeconds(TLinkNativeNowNs(), queryTimeout) <= 0) {
            CFRelease(root); root = NULL;
            return TLinkAXError(@"ui_cancelled_or_timed_out", nil);
        }
`;
    assert.ok(source.includes(rootGuard));
    assert.ok(source.includes('screen, scanned - 1, &window);'));
    const restored=source.replace(axAttributes(source),legacyAXAttributes).replace(rootGuard,'')
        .replace('screen, scanned - 1, &window);','screen, scanned - 1);');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'38d8ccaad0476a69019212bce654a1cd3bed6e3e04a264ea3860e4ab73715a0c',
        'complete preceding C05b AX, root query, snapshot/action/foreground/authority/symbol contract');
    return restored;
}
