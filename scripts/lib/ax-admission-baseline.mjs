import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
export const axAdmissionState=`static TLinkAXAdmission::State &TLinkAXAdmissionState(void)
{
    static TLinkAXAdmission::State state;
    return state;
}

`;
export const axAdmissionGate=`    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
`;
export function restoreAXAdmission(source){
    const original=source;
    assert.equal(source.split(axAdmissionGate).length-1,3,'exactly three shared public query admissions');
    for(const [signature,marker] of [
        ['NSDictionary *TLinkAXCopySnapshot(pid_t','    __block NSDictionary *result = nil;'],
        ['NSDictionary *TLinkAXFindElement(','    NSMutableDictionary *options = [NSMutableDictionary dictionary];'],
        ['NSDictionary *TLinkAXElementAtPoint(','    __block NSDictionary *result = nil;'],
    ]){
        const a=source.indexOf(signature),gate=source.indexOf(axAdmissionGate,a),point=source.indexOf(marker,a);
        assert.ok(a>=0&&gate>a&&point==gate+axAdmissionGate.length,'admission after validation/stop before queue/options work');
    }
    for(const part of ['#include "TLinkAXAdmission.h"\n',axAdmissionState,'        @"max_pending_queries": @(TLinkAXAdmission::MaxPending),\n']){
        assert.equal(source.split(part).length-1,1);source=source.replace(part,'');
    }
    source=source.replaceAll(axAdmissionGate,'');
    assert.notEqual(source,original);
    assert.equal(createHash('sha256').update(source).digest('hex'),'cf535ceb80b0d4dd442e3b699c2bcaf4f5a1468a1b0000dd5277761eb4e39721',
        'complete preceding C05m query/validation/cancel/deadline/owner/foreground/action/authority source');
    return source;
}
