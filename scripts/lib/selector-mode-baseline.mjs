import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
const read=name=>readFileSync(new URL('../../'+name,import.meta.url),'utf8').replaceAll('\r\n','\n');
export const selectorBeforeSharedMode=read('test/fixtures/ax-selector-before-c05af.inc');
export const selectorPlanBeforeCopy=read('test/fixtures/ax-selector-plan-before-c05af.inc');
export function restoreSelectorMode(source){
    const current='    TLinkAXSelectorPlan::Mode sharedMode(mode),exactMode(@"exact");\n    TLinkAXSelectorPlan::Text identifierPlan(identifier, sharedMode, caseSensitive);\n    TLinkAXSelectorPlan::Text rolePlan(role, exactMode, caseSensitive);\n    TLinkAXSelectorPlan::Text textPlan(text, sharedMode, caseSensitive);';
    const previous='    TLinkAXSelectorPlan::Text identifierPlan(identifier, mode, caseSensitive);\n    TLinkAXSelectorPlan::Text rolePlan(role, @"exact", caseSensitive);\n    TLinkAXSelectorPlan::Text textPlan(text, mode, caseSensitive);';
    assert.equal(source.split(current).length-1,1);source=source.replace(current,previous);
    assert.equal(hash(source),'8090db54fc12ed08e94c931a40cd2906b5a78fc406617f6d31b14d5a81cf81cc','complete preceding AX source with unshared modes');return source;
}
export function checkSelectorModeCore(){assert.equal(hash(read('shared/TLinkAXSelectorMode.h')),'b5b3247017dfc362876999a54f169cbb767ce2fa494d86b715ba13a6cb1dc784','complete selector mode state');}
