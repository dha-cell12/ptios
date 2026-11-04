import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreSupervisorEnsure} from './supervisor-ensure-admission-baseline.mjs';
export const legacySupervisorChild=readFileSync(new URL('../../test/fixtures/supervisor-before-c06z.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function childRetirement(source){const a=source.indexOf('// BEGIN direct child retirement identity.'),b=source.indexOf('// END direct child retirement identity.\n\n',a);assert.ok(a>=0&&b>a);return source.slice(a,b+'// END direct child retirement identity.\n\n'.length);}
export function childSpawn(source){const a=source.indexOf('- (void)spawnLocked\n');let b=source.indexOf('// BEGIN direct child retirement identity.',a);if(b<0)b=source.indexOf('- (void)handleChildExit:',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreSupervisorChild(source){
    source=restoreSupervisorEnsure(source);
    const allocation='    NSObject *childIdentity = [NSObject new];\n    if (!childIdentity) {\n        [self emitLog:@"supervisor: child identity unavailable; explicit ensure required"];\n        return;\n    }\n';
    const restored=source.replace('    NSObject *_directChildIdentity;\n','').replace(childRetirement(source),'').replace(allocation,'')
        .replaceAll('        self->_directChildIdentity = nil;\n','').replace('    if (shouldReplace) self->_directChildIdentity = nil;\n','')
        .replace('    self->_directChildIdentity = childIdentity;\n','')
        .replace('[self retireDirectChildLocked:childIdentity waitResult:w status:status expectedPid:pid];','[self handleChildExit:w status:status expectedPid:pid];');
    assert.equal(restored,legacySupervisorChild,'complete previous supervisor timer/wait/exit/lifecycle/helper/probe/transport source');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'ecc40225b9f796579363a0ea167e93af73132d382f64fe0c2abd1135ed94a56a');
    return restored;
}
