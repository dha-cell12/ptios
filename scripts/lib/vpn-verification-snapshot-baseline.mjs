import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyVerificationSnapshot=readFileSync(new URL('../../test/fixtures/vpn-verification-before-c06ad.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
function configure(source){const a=source.indexOf('static NSDictionary *TLinkVPNPrivateConfigureLegacySync('),b=source.indexOf('NSDictionary *TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreVerificationSnapshot(source){
    const a=legacyVerificationSnapshot.indexOf('    NSArray<NSDictionary *> *beforeRecords ='),b=legacyVerificationSnapshot.indexOf('    NSString *requestedName =',a);
    assert.ok(a>=0&&b>a);
    const snapshot=`    NSUInteger beforeRecordCount = 0;
    NSMutableSet<NSString *> *beforeIdentifiers = nil;
    @autoreleasepool {
        NSArray<NSDictionary *> *beforeRecords =
            TLinkVPNPrivateConfigurationRecords(store);
        beforeIdentifiers = [NSMutableSet set];
        for (NSDictionary *record in beforeRecords) {
            NSString *identifier = record[@"identifier"];
            if (identifier.length > 0) [beforeIdentifiers addObject:identifier];
        }
        beforeRecordCount = beforeRecords.count;
    }
`;
    const expected=legacyVerificationSnapshot.replaceAll('beforeRecords.count','beforeRecordCount').replace(legacyVerificationSnapshot.slice(a,b),snapshot);
    assert.equal(configure(source),expected,'only initial snapshot pool/scalar count changes; identifier aliases, create/verify/result/effects unchanged');
    const restored=source.replace(configure(source),legacyVerificationSnapshot);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'70f2e8233a478b72ac6e1b87300d66e26bea2dbe88890a487457a76f3a5b7ebf',
        'complete pre-C06ad manager, record membership/private/public backend/authority source');
    return restored;
}
