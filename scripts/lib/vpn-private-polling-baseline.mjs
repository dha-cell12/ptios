import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const before=readFileSync(new URL('../../test/fixtures/vpn-manager-before-c04j.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
assert.equal(hash(before),'04f18dd37285f9824187e42a6a6dbedc38cd374401d3b2e119d5da3a054367cb');
function between(s,a,b){const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);}
export function privateTransition(source){return between(source,'static NSDictionary *TLinkVPNPrivateSetConnectedSync(','static NSDictionary *TLinkVPNPrivateRunSafely(');}
export const legacyPrivateTransition=privateTransition(before);
export function privatePollingAdapter(source){return between(source,'// BEGIN continuous private VPN transition polling.','static NSDictionary *TLinkVPNPrivateSetConnectedSync(');}
export function restoreVPNPrivatePolling(source){
    const current=between(privateTransition(source),'    TLinkVPNPrivatePolling::Window window(', '    return TLinkVPNResult(false, @"vpn_private_transition_timeout",');
    const old=between(legacyPrivateTransition,'    ((void (*)(id, SEL))objc_msgSend)(connection, action);', '    return TLinkVPNResult(false, @"vpn_private_transition_timeout",');
    const restored=source.replace('#include "TLinkVPNPrivatePolling.h"\n#include "TLinkHelperSocketIO.h"\n','')
        .replace(privatePollingAdapter(source),'').replace(current,old);
    assert.equal(hash(restored),'47979bd04cf668e71f66eeabbff598c9aff869b9f7eadfcb65849c74a84fa9e8',
        'complete prior public/root manager, private configuration/cleanup/authority/parser and transition preflight/replies');
    return restored;
}
