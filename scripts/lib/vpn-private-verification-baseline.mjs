import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const before=readFileSync(new URL('../../test/fixtures/vpn-manager-before-c04j.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
assert.equal(hash(before),'04f18dd37285f9824187e42a6a6dbedc38cd374401d3b2e119d5da3a054367cb');
function between(s,a,b){const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);}
export function privateConfigure(source){return between(source,'static NSDictionary *TLinkVPNPrivateConfigureLegacySync(','NSDictionary *TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper(');}
export const legacyPrivateConfigure=privateConfigure(before);
export function privateVerificationAdapter(source){return between(source,'// BEGIN bounded private VPN creation verification wait.','static NSDictionary *TLinkVPNPrivateConfigureLegacySync(');}
export function privateVerificationLoop(source){return between(privateConfigure(source),'    NSDictionary *newRecord = nil;','    if (!newRecord) {\n        return TLinkVPNResult(false,');}
export function restoreVPNPrivateVerification(source){
    const restored=source.replace(privateVerificationAdapter(source),'').replace(privateVerificationLoop(source),privateVerificationLoop(before));
    assert.equal(hash(restored),'df09d035dc57440a7c7463d2e99a98c97a6553d3da2993c531d8fd50d2e6ac50',
        'complete prior manager, create options/action, ownership/persistence, cleanup, private/public transitions and replies');
    return restored;
}
