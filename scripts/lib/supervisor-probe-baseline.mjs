import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreSupervisorWatch} from './supervisor-watch-baseline.mjs';
export const legacySupervisorProbe=readFileSync(new URL('../../test/fixtures/supervisor-probe-before-c06u.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function supervisorProbe(source){const a=source.indexOf('- (NSDictionary *)streamdHelloStatusLocked'),b=source.indexOf('- (BOOL)ensureServiceLockedWithReplace:',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreSupervisorProbe(source){
    source=restoreSupervisorWatch(source);
    const restored=source.replace(supervisorProbe(source),legacySupervisorProbe);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'23a92e4a2ccf938cf0d758f3014b92eade78a2f59ebe2c0192cc7cab9f288588',
        'complete prior supervisor: transport/helper/lifecycle/watchdog/fallback/authority source');
    // Probe decisions and effects are retained apart from the shared local read.
    const old=legacySupervisorProbe.slice(legacySupervisorProbe.indexOf('- (BOOL)probeTaskServerAndUpdateLocked:'));
    const current=supervisorProbe(source).slice(supervisorProbe(source).indexOf('- (BOOL)probeTaskServerAndUpdateLocked:'));
    assert.equal(current.replace('    // One probe-local hello keeps PID and fallback path in the same response.\n    NSDictionary *hello = [self streamdHelloStatusLocked];\n    pid_t pid = (pid_t)[hello[@"pid"] intValue];','    pid_t pid = [self streamdPidFromHelloStatusLocked];')
        .replace('            NSString *reportedPath = hello[@"launch_executable_path"];\n            runningPath = [reportedPath isKindOfClass:[NSString class]] ? reportedPath : @"";','            runningPath = [self streamdLaunchPathFromHelloStatusLocked];'),old);
    return restored;
}
