import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreVerificationSnapshot} from './vpn-verification-snapshot-baseline.mjs';
export const legacyVPNRecords=readFileSync(new URL('../../test/fixtures/vpn-records-before-c06ac.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function vpnRecords(source){const a=source.indexOf('static NSArray<NSDictionary *> *TLinkVPNPrivateConfigurationRecords('),b=source.indexOf('static NSDictionary *TLinkVPNPrivateFindConfiguration(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreVPNRecords(source){
    source=restoreVerificationSnapshot(source);
    const oldScan=`            for (NSDictionary *existing in records) {
                if ([existing[@"identifier"] isEqualToString:identifier]) {
                    return;
                }
            }
`;
    const newScan=`            if (mutableIdentifiers || [identifier isKindOfClass:[NSMutableString class]]) {
                // Preserve live identifier comparisons for aliased mutable inputs.
                for (NSDictionary *existing in records) {
                    if ([existing[@"identifier"] isEqualToString:identifier]) {
                        return;
                    }
                }
            } else if ([knownIdentifiers containsObject:identifier]) {
                return;
            }
`;
    const track=`            if ([identifier isKindOfClass:[NSMutableString class]]) mutableIdentifiers = YES;
            if (!mutableIdentifiers) [knownIdentifiers addObject:identifier];
`;
    const expected=legacyVPNRecords.replace('    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];\n',
        '    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];\n    NSMutableSet<NSString *> *knownIdentifiers = [NSMutableSet set];\n    __block BOOL mutableIdentifiers = NO;\n')
        .replace(oldScan,newScan).replaceAll('            }];\n','            }];\n'+track);
    assert.equal(vpnRecords(source),expected,'only membership index/mutable fallback changes in complete record collector');
    const restored=source.replace(vpnRecords(source),legacyVPNRecords);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'defade24c7b588bb8f4bb7a2ed2281c773101a278ee724cb0ccb894175ecf215',
        'complete pre-C06ac manager/private selectors/polling/profile/authority source');
    return restored;
}
