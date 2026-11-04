import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXSnapshot} from './ax-snapshot-baseline.mjs';
export const legacyAXSymbols=readFileSync(new URL('../../test/fixtures/ax-symbols-before-c05a.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axSymbols(source){const a=source.indexOf('static NSDictionary *TLinkAXLockState(void)'),b=source.indexOf('static BOOL TLinkAXPrepare(void)',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXSymbols(source){
    source=restoreAXSnapshot(source);
    let expected=legacyAXSymbols;
    for(const [variable,path,first,second] of [
        ['sbs','/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices','SBSSpringBoardServerPort','SBGetScreenLockStatus'],
        ['security','/System/Library/Frameworks/Security.framework/Security','SecTaskCreateFromSelf','SecTaskCopyValueForEntitlement'],
    ]){
        const cached=`    static TLinkAXSymbols::Cache symbols(
        "${path}",
        "${first}", "${second}");
    const auto resolved = symbols.load(
        [](const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); },
        [](void *handle, const char *name) { return dlsym(handle, name); },
        [](void *handle) { dlclose(handle); });
    void *${variable} = resolved.handle;`;
        expected=expected.replace(`    void *${variable} = dlopen("${path}", RTLD_LAZY | RTLD_LOCAL);`,cached)
            .replace(`dlsym(${variable}, "${first}")`,'resolved.first')
            .replace(`dlsym(${variable}, "${second}")`,'resolved.second');
    }
    assert.equal(axSymbols(source),expected,'only symbol loader changes; complete live lock/notify/entitlement/CF ownership logic retained');
    const restored=source.replace('#include "TLinkAXSymbolCache.h"\n','').replace(axSymbols(source),legacyAXSymbols);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'3b4a24dff884447f99d78529a742c59d4a92f9b8ca74b141f979f4bd6508a9ab',
        'complete preceding AX source, serialization/traversal/output/foreground/action/authority behavior');
    return restored;
}
