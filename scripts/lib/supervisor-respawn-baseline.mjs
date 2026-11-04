import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreSupervisorChild} from './supervisor-child-baseline.mjs';
export const legacySupervisorRespawn=readFileSync(new URL('../../test/fixtures/supervisor-before-c06y.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function respawnMethods(source){const a=source.indexOf('// BEGIN owned supervisor respawn.'),b=source.indexOf('// END owned supervisor respawn.\n\n',a);assert.ok(a>=0&&b>a);return source.slice(a,b+'// END owned supervisor respawn.\n\n'.length);}
export const respawnFields='    dispatch_source_t _respawnTimer;\n    NSObject *_respawnIdentity;\n';
export function restoreSupervisorRespawn(source){
    source=restoreSupervisorChild(source);
    const old='    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self->_queue, ^{\n        if (self->_autoRespawn && !self->_running) {\n            [self spawnLocked];\n        }\n    });';
    const restored=source.replace(respawnMethods(source),'').replace(respawnFields,'')
        .replaceAll('        [self cancelPendingRespawnLocked];\n','').replaceAll('    [self cancelPendingRespawnLocked];\n','')
        .replace('    [self scheduleRespawnLockedWithDelay:delay];',old);
    assert.equal(restored,legacySupervisorRespawn,'complete pre-C06y lifecycle/helper/transport/probe/watcher source');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'ca5dc86a774935c33597a10e03eaf78061ff0803c09eddcdfd9df8eb73f1ade7');
    return restored;
}
