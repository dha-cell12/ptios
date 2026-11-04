import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreVPNRecords} from './vpn-records-baseline.mjs';
export const legacyIKEv2Sync=readFileSync(new URL('../../test/fixtures/vpn-ikev2-sync-before-c06s.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function ikev2Sync(source){const a=source.indexOf('NSDictionary *TLinkVPNConfigureIKEv2SynchronouslyForHelper('),b=source.indexOf('void TLinkVPNSetOnDemandEnabled(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreIKEv2Sync(source){
    source=restoreVPNRecords(source);
    const restored=source.replace('#include "TLinkVPNBrokerBudget.h"\n','').replace(ikev2Sync(source),legacyIKEv2Sync);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'e157887d41c3c41651e12d75f495228df778003a358b042d0234b3bceeb4698f',
        'complete pre-C06s manager, private/public backend/cleanup/verification/authority/source');
    const suffix=s=>s.slice(s.indexOf('    if (!completedResult) {'));
    assert.equal(suffix(ikev2Sync(source)),suffix(legacyIKEv2Sync),'complete timeout/decoration result contract');
    return restored;
}
