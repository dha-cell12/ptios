import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacySupervisorTask=readFileSync(new URL('../../test/fixtures/supervisor-task-before-c06t.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function supervisorTask(source){const a=source.indexOf('- (NSString *)sendLocalTaskLineLocked:'),b=source.indexOf('- (pid_t)streamdPidFromHelloStatusLocked',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreSupervisorTask(source){
    const restored=source.replace('#include "../../shared/TLinkSupervisorTaskIO.h"\n','').replace(supervisorTask(source),legacySupervisorTask);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'ce5805c4da63ca48be09a6456af322a8bd0f0253b395cea333708771eeb68a5c',
        'complete preceding supervisor: helper/ensure/stop/restart/probe interpretation/watchdog/delegate source');
    return restored;
}
