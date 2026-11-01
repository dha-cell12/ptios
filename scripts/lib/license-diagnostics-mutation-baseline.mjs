import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreLicenseReload} from './license-reload-baseline.mjs';
const hash=s=>createHash('sha256').update(s).digest('hex');
const before=readFileSync(new URL('../../test/fixtures/license-diagnostics-before-c06o.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
const update='- (void)updateDiagnostics:(NSDictionary *)values refreshHistoryEvent:(NSDictionary *)event\n';
const failure='- (void)recordRefreshFailure:';
const declaration='- (void)updateDiagnostics:(NSDictionary *)values refreshHistoryEvent:(NSDictionary *)event stateMutation:(void (^)(NSMutableDictionary *))mutation;\n';
function between(s,a,b){const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);}
export function restoreLifecycleDiagnosticsMutation(source){
    source=restoreLicenseReload(source);
    const oldUpdate=before.slice(0,before.indexOf(failure)),oldFailure=before.slice(before.indexOf(failure));
    const expectedFailure=oldFailure.replace('    @synchronized (self) {\n        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath];',
        '    [self updateDiagnostics:nil refreshHistoryEvent:event stateMutation:^(NSMutableDictionary *existing) {')
        .replace('        [self updateDiagnostics:@{','        [existing addEntriesFromDictionary:@{')
        .replace('        } refreshHistoryEvent:event];\n    }','        }];\n    }];');
    assert.equal(between(source,failure,'- (void)refreshForTrigger:'),expectedFailure,'complete prior failure math/jitter/fields retained');
    const restored=source.replace(declaration,'').replace(between(source,update,'- (void)updateDiagnostics:(NSDictionary *)values\n'),oldUpdate)
        .replace(expectedFailure,oldFailure);
    assert.equal(hash(restored),'6561f5e0cadc2f863fc04739c98a7dce75fc60867a1320e1f32dc250e8c7b164',
        'complete pre-C06o coordinator, subscriber/decision/authority/HTTP/UI/diagnostic schema source');
    return restored;
}
