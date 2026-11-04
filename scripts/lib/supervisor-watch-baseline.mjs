import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreSupervisorRespawn} from './supervisor-respawn-baseline.mjs';
export const legacySupervisorWatch=readFileSync(new URL('../../test/fixtures/supervisor-watch-before-c06x.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function watchWait(source){const a=source.indexOf('        int status = 0;',source.indexOf('- (void)spawnLocked\n')),b=source.indexOf('        dispatch_async(self->_queue,',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function watchExit(source){const a=source.indexOf('- (void)handleChildExit:'),b=source.indexOf('\n@end',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreSupervisorWatch(source){
    source=restoreSupervisorRespawn(source);
    const restored=source.replace('#include "../../shared/TLinkSupervisorWatch.h"\n','').replace('    uint64_t _lastSpawnContinuous;','    NSDate *_lastSpawn;')
        .replace('    self->_lastSpawnContinuous = TLinkHelperIO::nowMs();','    self->_lastSpawn = [NSDate date];')
        .replace(watchWait(source),watchWait(legacySupervisorWatch)).replace(watchExit(source),watchExit(legacySupervisorWatch));
    assert.equal(restored,legacySupervisorWatch,'complete previous supervisor helper/lifecycle/transport/probe/watch source');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'a9de70cd9cc096afd0a350cfbdcea84b394d9670e23455814b6952dc2c5bea82');
    const current=watchExit(source).replace('    const uint64_t delayMs = TLinkSupervisorWatch::remainingMs(self->_lastSpawnContinuous,\n        TLinkHelperIO::nowMs(), static_cast<uint64_t>(kSCRespawnThrottle * 1000.0));\n    NSTimeInterval delay = delayMs / 1000.0;',
        '    NSTimeInterval since = [[NSDate date] timeIntervalSinceDate:self->_lastSpawn];\n    NSTimeInterval delay = (since >= kSCRespawnThrottle) ? 0.0 : (kSCRespawnThrottle - since);');
    assert.equal(current,watchExit(legacySupervisorWatch),'complete exit state/log/respawn gate/delivery policy');
    return restored;
}
