import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXLazyFrontmost} from './ax-lazy-frontmost-baseline.mjs';
const frozen=name=>readFileSync(new URL('../../test/fixtures/'+name,import.meta.url),'utf8').replaceAll('\r\n','\n');
export const legacyAXEntitlement=frozen('ax-entitlement-before-c05h.inc');
export const legacyAXCapability=frozen('ax-capability-before-c05h.inc');
export function axEntitlement(source){const a=source.indexOf('static id TLinkAXEntitlementValue('),b=source.indexOf('static BOOL TLinkAXPrepare(void)',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function axCapability(source){const a=source.indexOf('NSDictionary *TLinkAXCapabilitySnapshot(void)'),b=source.indexOf('static NSString *TLinkAXFrontmostBundleID(void)',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXEntitlementTask(source){
    source=restoreAXLazyFrontmost(source);
    const entitlement=legacyAXEntitlement
        .replace('static id TLinkAXEntitlementValue(NSString *name)','static id TLinkAXEntitlementValue(NSString *name, CFTypeRef *sharedTask = nullptr)')
        .replace('    CFTypeRef task = createTask(kCFAllocatorDefault);',`    CFTypeRef task = sharedTask ? *sharedTask : NULL;
    if (!task) {
        task = createTask(kCFAllocatorDefault);
        if (sharedTask) *sharedTask = task;
    }`)
        .replace(`    CFTypeRef value = copyValue(task, (__bridge CFStringRef)name, &error);
    CFRelease(task);
    if (error) CFRelease(error);
    return value ? CFBridgingRelease(value) : nil;`,`    CFTypeRef value = NULL;
    @try {
        value = copyValue(task, (__bridge CFStringRef)name, &error);
        id result = value ? CFBridgingRelease(value) : nil;
        value = NULL;
        return result;
    } @finally {
        if (!sharedTask) CFRelease(task);
        if (error) CFRelease(error);
        if (value) CFRelease(value);
    }`);
    const capability=legacyAXCapability.replace(`    for (NSString *name in names) {
        id value = TLinkAXEntitlementValue(name);
        entitlements[name] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
    }`,`    CFTypeRef entitlementTask = NULL;
    @try {
        for (NSString *name in names) {
            id value = TLinkAXEntitlementValue(name, &entitlementTask);
            entitlements[name] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
        }
    } @finally {
        if (entitlementTask) CFRelease(entitlementTask);
    }`);
    assert.equal(axEntitlement(source),entitlement,'only optional per-probe task reuse and CF finally cleanup; symbols/value/error rules preserved');
    assert.equal(axCapability(source),capability,'only per-probe task owner/forwarding; all capability keys, BOOL normalization and live probes preserved');
    const restored=source.replace(axEntitlement(source),legacyAXEntitlement).replace(axCapability(source),legacyAXCapability);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'b935fc0007c80a22e3fd88884e7ab574a17d0b15f94758514d0d2ca8c1bde3f2',
        'complete preceding C05g AX/foreground/snapshot/selector/action/authority source');
    return restored;
}
