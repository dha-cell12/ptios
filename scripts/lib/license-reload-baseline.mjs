import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyReload=readFileSync(new URL('../../test/fixtures/license-reload-before-c06p.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function rootReload(source){const a=source.indexOf('static NSString *SCLicenseRootfullReloadRequest(void)'),b=source.indexOf('\n#endif',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreLicenseReload(source){
    const restored=source.replace('#include "../../shared/TLinkLicenseReloadIO.h"\n','').replace(rootReload(source),legacyReload.trimEnd());
    assert.equal(createHash('sha256').update(restored).digest('hex'),'47984b7b3ebfcb33899f18f3f862740d1f0e459e2491f9bafc9cda6d0e52e030',
        'complete previous coordinator, TrollStore reload, retry/diagnostics/HTTP/authority/subscription source');
    return restored;
}
