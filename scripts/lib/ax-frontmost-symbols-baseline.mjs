import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXEntitlementTask} from './ax-entitlement-task-baseline.mjs';
export const legacyAXFrontmost=readFileSync(new URL('../../test/fixtures/ax-frontmost-before-c05g.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export const legacyAXSymbolHeader=readFileSync(new URL('../../test/fixtures/ax-symbol-cache-before-c05g.h',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axFrontmost(source){const a=source.indexOf('static NSString *TLinkAXFrontmostBundleID(void)'),b=source.indexOf('static NSString *TLinkAXBundleIDForExecutablePath(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXFrontmostSymbols(source){
    source=restoreAXEntitlementTask(source);
    const expected=legacyAXFrontmost
        .replace('    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);',`    static TLinkAXSymbols::Cache copySymbols(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        "SBSCopyFrontmostApplicationDisplayIdentifier", "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay");
    const auto resolved = copySymbols.load(
        [](const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); },
        [](void *handle, const char *name) { return dlsym(handle, name); },
        [](void *handle) { dlclose(handle); });
    void *sbs = resolved.handle;`)
        .replace('dlsym(sbs, symbols[index])','(index == 0 ? resolved.first : resolved.second)')
        .replace(`    mach_port_t (*serverPort)(void) =
        (mach_port_t (*)(void))dlsym(sbs, "SBSSpringBoardServerPort");
    void (*legacyFrontmost)(mach_port_t, char *) =
        (void (*)(mach_port_t, char *))dlsym(sbs, "SBFrontmostApplicationDisplayIdentifier");`,`    static TLinkAXSymbols::Symbol serverPortSymbol("SBSSpringBoardServerPort");
    static TLinkAXSymbols::Symbol legacyFrontmostSymbol("SBFrontmostApplicationDisplayIdentifier");
    mach_port_t (*serverPort)(void) = (mach_port_t (*)(void))serverPortSymbol.load(sbs,
        [](void *handle, const char *name) { return dlsym(handle, name); });
    void (*legacyFrontmost)(mach_port_t, char *) = (void (*)(mach_port_t, char *))legacyFrontmostSymbol.load(sbs,
        [](void *handle, const char *name) { return dlsym(handle, name); });`);
    assert.equal(axFrontmost(source),expected,'only foreground loader/symbol reuse; provider order, fresh values, fallback/parser/CF/exception behavior preserved');
    const restored=source.replace(axFrontmost(source),legacyAXFrontmost);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'1aa144ed38ee83d696cab05b5bb2192f0c6eb9569754807ea9a45b08d4bd4c9c',
        'complete preceding C05f AX snapshot/selector/foreground PID/action/authority contract');
    return restored;
}
export function checkAXSymbolHeader(source){
    const a=source.indexOf('// A fixed symbol borrowed'),b=source.indexOf('// Fixed library/symbol names per instance.',a);
    assert.ok(a>=0&&b>a);
    assert.equal(source.slice(0,a)+source.slice(b),legacyAXSymbolHeader,'complete preceding two-symbol cache source unchanged');
}
