import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacySupervisorEnsure=readFileSync(new URL('../../test/fixtures/supervisor-before-c06aa.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export const ensureField='    std::shared_ptr<TLinkSupervisorEnsureAdmission::State> _ensureAdmission;\n';
export const ensureInit='        _ensureAdmission = std::make_shared<TLinkSupervisorEnsureAdmission::State>();\n';
export function ensureEntry(source){const a=source.indexOf('- (void)ensureServiceWithStartPermission:'),b=source.indexOf('- (void)stop\n',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreSupervisorEnsure(source){
    const current=ensureEntry(source);const a=current.indexOf('    // BEGIN bounded supervisor ensure admission.'),b=current.indexOf('    // END bounded supervisor ensure admission.\n',a);assert.ok(a>=0&&b>a);
    const previous=current.replace(current.slice(a,b+'    // END bounded supervisor ensure admission.\n'.length),'')
        .replace('        TLinkSupervisorEnsureAdmission::Scope admissionScope{ensureLease};\n','')
        .replaceAll('                ensureLease->release();\n','').replaceAll('            ensureLease->release();\n','');
    assert.equal(previous,ensureEntry(legacySupervisorEnsure),'complete previous permission/helper/timer/ensure/fallback/completion source');
    const restored=source.replace('#include "../../shared/TLinkSupervisorEnsureAdmission.h"\n','').replace(ensureField,'').replace(ensureInit,'').replace(current,previous);
    assert.equal(restored,legacySupervisorEnsure,'complete prior supervisor child/watcher/lifecycle/helper/transport/probe source');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'dcb8c72659faca3bcdb7ec4bdebe4ca213bc2bc1ee274a390295782bb0232082');
    return restored;
}
export function restoreSupervisorEnsureHeader(source){
    const addition='// Up to eight ensures may be active/queued per instance. Excess requests receive\n// supervisor_ensure_queue_full on main without invoking startPermission.\n';
    assert.equal(source.split(addition).length,2);return source.replace(addition,'');
}
