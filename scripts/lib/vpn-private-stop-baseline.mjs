import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const oldVPNPrivateScriptCall='TLinkVPNRunPrivateConfigurationHelper(helperPath, request)';
export const vpnPrivateScriptCall='TLinkVPNRunPrivateConfigurationHelperWithStop(helperPath, request, ^BOOL {\n                    return TLinkScriptStopRequested(strongSession);\n                })';
export function restoreVPNPrivateCaller(source){
    assert.equal(source.split(vpnPrivateScriptCall).length,2,'one script VPN stop adapter');
    const restored=source.replace(vpnPrivateScriptCall,oldVPNPrivateScriptCall);
    assert.equal(hash(restored),'1f77d0902cccfcb4d9d768ee3e4e58a0cbea01f4fb6771417a1cef3484ec82f3','complete pre-C06b TrollStore script/server source');
    return restored;
}
export function restoreVPNPrivateStop(source){
    const start=source.indexOf('    // BEGIN VPN helper caller stop.'),end=source.indexOf('    // END VPN helper caller stop.\n',start);
    assert.ok(start>=0&&end>start);
    const wrapper='\nNSDictionary *TLinkVPNRunPrivateConfigurationHelper(\n    NSString *helperPath,\n    NSDictionary *configuration)\n{\n    return TLinkVPNRunPrivateConfigurationHelperWithStop(helperPath, configuration, nil);\n}\n';
    assert.ok(source.endsWith(wrapper));
    const restored=source.slice(0,-wrapper.length)
        .replace(source.slice(start,end+'    // END VPN helper caller stop.\n'.length),'')
        .replace('NSDictionary *TLinkVPNRunPrivateConfigurationHelperWithStop(','NSDictionary *TLinkVPNRunPrivateConfigurationHelper(')
        .replace('    NSDictionary *configuration,\n    TLinkVPNPrivateRequestShouldStop shouldStop)','    NSDictionary *configuration)')
        .replaceAll('    if (stopped()) return TLinkVPNRequestResult(NO, @"vpn_private_helper_cancelled", nil);\n','')
        .replace('child.wait(TLinkVPNHelperChild::TimeoutMs, TLinkVPNHelperChild::GraceMs, cancellation)','child.wait()')
        .replace('            childResult.reason == TLinkVPNHelperChild::Reason::Stopped\n                ? @"vpn_private_helper_cancelled" : childResult.reason == TLinkVPNHelperChild::Reason::Timeout','            childResult.reason == TLinkVPNHelperChild::Reason::Timeout');
    assert.equal(hash(restored),'d8569f97581ab17b181e3fad12ec376f13d32454727bf1749c96fd43fc989bec','complete pre-C06b request transport');
    return restored;
}
