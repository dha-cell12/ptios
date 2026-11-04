import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const frozen=name=>readFileSync(new URL('../../test/fixtures/'+name,import.meta.url),'utf8').replaceAll('\r\n','\n');
export const legacyAXLazyFrontmost=frozen('ax-frontmost-before-c05i.inc');
const legacyHeader=frozen('ax-symbol-cache-before-c05i.h');
export function restoreAXLazyFrontmost(source){
    const a=source.indexOf('static NSString *TLinkAXFrontmostBundleID(void)'),b=source.indexOf('static NSString *TLinkAXBundleIDForExecutablePath(',a);assert.ok(a>=0&&b>a);
    const expected=legacyAXLazyFrontmost
        .replace('        [](void *handle) { dlclose(handle); });','        [](void *handle) { dlclose(handle); }, false);')
        .replace('        CFStringRef (*copyFrontmost)(void) = (CFStringRef (*)(void))(index == 0 ? resolved.first : resolved.second);',`        void *copySymbol = index == 0 ? resolved.first : copySymbols.loadSecond(
            [](void *handle, const char *name) { return dlsym(handle, name); });
        CFStringRef (*copyFrontmost)(void) = (CFStringRef (*)(void))copySymbol;`);
    assert.equal(source.slice(a,b),expected,'only defer second foreground symbol until fallback; provider order/values/CF/exception/parser source preserved');
    const restored=source.slice(0,a)+legacyAXLazyFrontmost+source.slice(b);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'cecfc1fb1e3263fed408f844d5ea320d0ae1b4c6a270d76ffb7904c901b9f723',
        'complete preceding C05h AX capability/foreground/snapshot/selector/action/authority contract');
    return restored;
}
export function restoreAXLazyHeader(source){
    const expected=legacyHeader
        .replace('Snapshot load(Open open,Lookup lookup,Close close){','Snapshot load(Open open,Lookup lookup,Close close,bool includeSecond=true){')
        .replace('return {handle,resolve(first_,handle,firstName_,lookup),resolve(second_,handle,secondName_,lookup)};',
            'return {handle,resolve(first_,handle,firstName_,lookup),includeSecond?resolve(second_,handle,secondName_,lookup):nullptr};')
        .replace('    }\n};\n}\n#endif',`    }
    // Resolve only when the caller actually reaches its fallback. Never opens
    // another handle; before successful load(), there is nothing to resolve.
    template<class Lookup>
    void *loadSecond(Lookup lookup){
        void *handle=handle_.load(std::memory_order_acquire);
        return handle?resolve(second_,handle,secondName_,lookup):nullptr;
    }
};
}
#endif`);
    assert.equal(source,expected,'only optional deferred second lookup/public resolver; default cache, handle ownership and borrowed Symbol unchanged');
    return legacyHeader;
}
