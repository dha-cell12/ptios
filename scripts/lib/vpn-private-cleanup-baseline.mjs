import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const before=readFileSync(new URL('../../test/fixtures/vpn-manager-before-c04j.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
assert.equal(hash(before),'04f18dd37285f9824187e42a6a6dbedc38cd374401d3b2e119d5da3a054367cb');
function section(s,a,b){const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y+b.length);}
export function privateCleanup(source){return section(source,'static NSDictionary *TLinkVPNPrivateRemoveOwnedProfileSync(void)','        @"removed": @(record != nil),\n    });\n}\n\n');}
export const legacyPrivateCleanup=privateCleanup(before);
export function privateCleanupAdapter(source){return section(source,'// BEGIN continuous private VPN cleanup wait.','// END continuous private VPN cleanup wait.\n\n');}
export function restoreVPNPrivateCleanup(source){
    const restored=source.replace(privateCleanupAdapter(source),'').replace(privateCleanup(source),legacyPrivateCleanup);
    assert.equal(hash(restored),'cd5b8d751dc0fb831606e0fa3950fabe734cd176db1f38edde44f2ad81e07ecd',
        'complete prior manager, verification/options/persistence, private/public transitions, cleanup preflight/delete/marker/publication source');
    // Only the disconnect wait changes inside the cleanup handler.
    const tail=s=>s.slice(s.indexOf('    if (record && !TLinkVPNPrivateDeleteConfiguration'));
    assert.equal(tail(privateCleanup(source)),tail(legacyPrivateCleanup));
    const pre=s=>s.slice(0,s.indexOf('            '+(s.includes('disconnectedInTime')?'TLinkVPNPrivatePolling::Window':'((void (*)(id, SEL))objc_msgSend)')));
    assert.equal(pre(privateCleanup(source)),pre(legacyPrivateCleanup));
    return restored;
}
