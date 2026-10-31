import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export function vpnControlPreflight(source){
    const start='// BEGIN narrow VPN control preflight.',end='// END narrow VPN control preflight.\n\n';
    const a=source.indexOf(start),b=source.indexOf(end,a+start.length);
    assert.ok(a>=0&&b>a,'narrow preflight source markers');
    return source.slice(a,b+end.length);
}
export function restoreVPNControlPreflight(source){
    const restored=source.replace(vpnControlPreflight(source),'');
    assert.equal(hash(restored),'5d2eef168f21beb6804547e9c6da28f34748212e1329d3d1321da97fb2bab931','complete previous entitlement/framework/private compatibility/diagnostic source');
    return restored;
}
export function restoreVPNControlPreflightHeader(source){
    const restored=source.replace('// Admission-only view: cached process entitlements and a fresh framework probe.\n// Full diagnostic/private compatibility and mutable VPN state are not evaluated.\nFOUNDATION_EXPORT NSDictionary *TLinkVPNControlPreflight(void);\n\n','');
    assert.equal(hash(restored),'a99050c0cc00c173154a7e7a228a598bf84b3bb817348fcc987a7c25293c87d9','complete previous public diagnostic API');
    return restored;
}
export function restoreBrokerControlPreflight(source,agent){
    const current=agent?'TLinkVPNAgentEntitlementReady(TLinkVPNControlPreflight())':'NSDictionary *preflight = TLinkVPNControlPreflight();';
    const previous=agent?'TLinkVPNAgentEntitlementReady(TLinkVPNAgentPreflight())':'NSDictionary *preflight = TLinkVPNForegroundPreflight();';
    assert.equal(source.split(current).length,2,'one ordinary control admission call');
    const restored=source.replace(current,previous);
    assert.equal(hash(restored),agent?'8019bcf1416319f0dece179490e3507865aee99b43a29da40699f3905cbb2fa5':'0172d5e889fdbabf8751f89c9a3a3e997fe81721bd871e5eb73e450dcc8b1e6a','complete previous broker authority/wait/IO/mutation/diagnostics source');
    return restored;
}
