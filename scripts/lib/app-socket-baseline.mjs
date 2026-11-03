import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAppSocket=readFileSync(new URL('../../test/fixtures/socket-client-before-c06w.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function appTaskRequest(source){const a=source.indexOf('// BEGIN bounded app task request.'),b=source.indexOf('// END bounded app task request.\n',a);assert.ok(a>=0&&b>a);return source.slice(a,b+'// END bounded app task request.\n'.length);}
const methods=s=>{const a=s.indexOf('+ ('),b=s.indexOf('+ (NSString *)requestTask:',a);assert.ok(a>=0&&b>a);return s.slice(a,b);};
export function restoreAppSocket(source){
    const restored=source.replace('#include "../../shared/TLinkAppTaskIO.h"\n','').replace(appTaskRequest(source)+'\n','').replace(methods(source),methods(legacyAppSocket));
    assert.equal(restored,legacyAppSocket,'complete previous imports/requestTask codec/class source');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'fb1a0b2228dfbc50f800a0e0c131840428c08965bb36667b9e8c774f99017b75');
    return restored;
}
