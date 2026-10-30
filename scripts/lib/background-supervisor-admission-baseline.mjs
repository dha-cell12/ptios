import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const once=(source,text)=>assert.equal(source.split(text).length,2,'one C06e addition: '+text.slice(0,80));
export function restoreSupervisorStartPermission(source){
    const wrapper='    [self ensureServiceWithStartPermission:nil completion:completion];\n}\n\n- (void)ensureServiceWithStartPermission:(BOOL (^)(void))startPermission\n                            completion:(void (^)(BOOL running, NSString *detail))completion\n{\n';
    const start=source.indexOf('        // BEGIN supervisor ensure start permission.'),end=source.indexOf('        // END supervisor ensure start permission.\n',start);
    assert.ok(start>=0&&end>start);once(source,wrapper);
    const gate=source.slice(start,end+'        // END supervisor ensure start permission.\n'.length);
    assert.match(gate,/admitted = startPermission\(\);/);
    assert.match(gate,/supervisor_ensure_cancelled_before_start/);
    assert.match(gate,/supervisor_ensure_admission_exception/);
    assert.match(gate,/if \(!admitted\)[\s\S]*dispatch_get_main_queue\(\)[\s\S]*return;/);
    assert.ok(source.indexOf(gate)<source.indexOf('        if ([self helperBusyLocked:@"ensure"])'));
    const restored=source.replace(wrapper,'').replace(gate,'');
    assert.equal(hash(restored),'5ab346f8af40b022231eb28d9235bad173bba2cd968e46090e7219a1445c8a65','complete pre-C06e supervisor');
    return restored;
}
export function restoreSupervisorStartHeader(source){
    const addition='// Optional admission runs once on the supervisor queue before any ensure effects.\n// NO or an exception refuses this request; completion remains asynchronous on main.\n// This does not cancel work after admission. The permission must be short/nonblocking.\n- (void)ensureServiceWithStartPermission:(BOOL (^)(void))startPermission\n                            completion:(void (^)(BOOL running, NSString *detail))completion;\n\n';
    once(source,addition);const restored=source.replace(addition,'');
    assert.equal(hash(restored),'4bba2d1f6c0ddab9117f82c1cbe260b2ac4d68d5971ef65b15d38282449a8db3','complete pre-C06e public supervisor API');
    return restored;
}
export function restoreBackgroundSupervisorPermission(source){
    const addition='[scheduler.supervisor ensureServiceWithStartPermission:^BOOL {\n                            return run->beginSupervisor();\n                        } completion:^(BOOL running, NSString *detail) {';
    once(source,addition);
    const restored=source.replace(addition,'[scheduler.supervisor ensureServiceWithCompletion:^(BOOL running, NSString *detail) {');
    assert.equal(hash(restored),'c65efdfe0ed5bd763c3ade66ad3ceb79644e6e64011ca9f5d521823dabb0916c','complete pre-C06e background scheduler');
    return restored;
}
export function restoreBackgroundSupervisorPhase(source){
    const addition='    // Called on the supervisor owner queue, after its queue residence.\n    bool beginSupervisor() {\n        std::lock_guard<std::mutex> guard(mutex_);\n        if (phase_!=Phase::Ensuring) return false;\n        phase_=Phase::SupervisorStarted;\n        return true;\n    }\n';
    once(source,addition);once(source,'Ready, Refreshing, Ensuring, SupervisorStarted, Finished');
    const restored=source.replace(addition,'').replace('Ready, Refreshing, Ensuring, SupervisorStarted, Finished','Ready, Refreshing, Ensuring, Finished');
    assert.equal(hash(restored),'7097eb51f5b14487928da5446a53ff7158f57c510fc47b4260eb5fcbaf5baed7','complete pre-C06e BGTask owner/timer/finish source');
    return restored;
}
