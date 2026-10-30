import assert from 'node:assert/strict';
import {restoreBackgroundSchedulerSubscription,restoreBackgroundTaskCleanup,backgroundRefreshSubscriber} from './lib/license-subscription-baseline.mjs';
import {restoreBackgroundSupervisorPermission,restoreBackgroundSupervisorPhase} from './lib/background-supervisor-admission-baseline.mjs';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const between=(s,a,b)=>{const x=s.indexOf(a),y=s.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return s.slice(x,y);};
const [source,before,owner]=await Promise.all(['stream-app/app/BackgroundServiceScheduler.mm','test/fixtures/background-scheduler-before-c06d.inc','shared/TLinkBackgroundTaskRun.h'].map(read));
assert.equal(createHash('sha256').update(before).digest('hex'),'7c3e43108982f4ebf077b1987a685906b78245d3babbd98505a35f1ffbef47c3');
const previousStage=restoreBackgroundSupervisorPermission(restoreBackgroundSchedulerSubscription(source));
restoreBackgroundSupervisorPhase(restoreBackgroundTaskCleanup(owner));
const addition=between(previousStage,'    // BEGIN owned background task run.','    // END owned background task run.')+'    // END owned background task run.\n';
const previous=between(before,'    NSMutableDictionary *completionState =','\n}\n\n@end');
assert.equal(previousStage.replace('#include "../../shared/TLinkBackgroundTaskRun.h"\n','').replace(addition,previous+'\n'),before,
    'complete previous registration/scheduling/diagnostic source and handler preamble preserved');
assert.doesNotMatch(addition,/dispatch_after|__block/);
assert.match(addition,/dispatch_resume\(timer\);\s*run->installTimer\(timer\)/);
assert.match(addition,/if \(!run->beginEnsure\(\)\) return;[\s\S]*ensureServiceWithCompletion/);
assert.match(addition,/if \(!run->beginRefresh\(\)\) return;[\s\S]*performBackgroundRefreshWithCompletion/);
assert.match(addition,/task.expirationHandler = nil;\s*\[task setTaskCompletedWithSuccess:success\]/);
assert.match(owner,/phase_=Phase::Finished;[\s\S]*completion=completion_; completion_=nil;[\s\S]*cancelTimer\(timer\);[\s\S]*if \(completion\) completion/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-background-task-safety\.mjs/);
console.log('Background task source passed: subscriber cleanup/late publication, single refresh/ensure admission, first-result completion, owned cancellable watchdog, late callback diagnostics suppression and complete previous scheduling source.');
if(process.platform!=='darwin')console.log('macOS complete current/frozen BGTask Foundation/GCD/ARC lifetime/race runtime included in CI; not run on this host.');
else{
    const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-background-task-'));
    function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
    try{
        const adapt=s=>s.slice(s.indexOf('static NSString *const kTLinkBackgroundRefreshIdentifier'));
        const legacy=adapt(before).replaceAll('SCBackgroundServiceScheduler','SCLegacyBackgroundScheduler').replaceAll('kTLink','kLegacy');
        await Promise.all([writeFile(join(temp,'BackgroundTaskUnderTest.inc'),adapt(source)),writeFile(join(temp,'BackgroundTaskLegacy.inc'),legacy),writeFile(join(temp,'BackgroundRefreshSubscriber.inc'),backgroundRefreshSubscriber(await read('stream-app/app/LicenseLifecycleCoordinator.mm')))]);
        const binary=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++11','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/background-task-runtime-test.mm'),'-o',binary]);run(binary,[]);
    }finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-background-task-'));await rm(temp,{recursive:true,force:true});}
}
