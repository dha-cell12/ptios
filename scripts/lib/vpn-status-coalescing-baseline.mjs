import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export function restoreBrokerStatus(source,agent){
    const prefix=agent?'TLinkVPNAgent':'TLinkVPNForeground';
    const start=source.indexOf('// BEGIN coalesced broker status.'),end=source.indexOf('// END coalesced broker status.\n\n',start);
    assert.ok(start>=0&&end>start);
    const block=source.slice(start,end+'// END coalesced broker status.\n\n'.length);
    let restored=source.replace(block,'').replace('#include "../../shared/TLinkVPNBrokerStatus.h"\n','');
    assert.equal(restored.split(prefix+'ReadStatus(completion);').length,3);
    restored=restored.replaceAll(prefix+'ReadStatus(completion);','TLinkVPNReadManagerStatus(completion);')
        .replace('    '+prefix+'StatusOwner().invalidate();\n','')
        .replace('        if (ticket->complete()) '+prefix+'StatusOwner().invalidate();','        (void)ticket->complete();');
    assert.equal(hash(restored),agent?'763ac60b242281bc7cb410e9e21e91bfb2b5328c29205fa6babb234978c13fe5':'27cc17c406766bd5c912943ff4fadec45b84ada6e1ba9be10eafe7abcc39f38d','complete pre-coalescing broker authority/admission/wait/diagnostic/IO/mutation source');
    return restored;
}
