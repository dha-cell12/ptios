import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
function section(source,start,end){const a=source.indexOf(start),b=source.indexOf(end,a+start.length);assert.ok(a>=0&&b>a,start);return source.slice(a,b+end.length);}
export function backgroundRefreshSubscriber(source){return section(source,'// BEGIN background refresh subscriber.','// END background refresh subscriber.\n\n');}
export function restoreLifecycleSubscription(source){
    const api=section(source,'// BEGIN background refresh subscription API.','// END background refresh subscription API.\n\n');
    assert.match(api,/removeObjectIdenticalTo:callback/);assert.match(api,/\[callback copy\]|\} copy\]/);
    assert.match(api,/__weak SCLicenseLifecycleCoordinator \*weakSelf/);
    const restored=source.replace(backgroundRefreshSubscriber(source),'').replace(api,'')
        .replace('@property(nonatomic, strong) NSMutableDictionary *refreshSubscriberCallbacks;\n','')
        .replace('@property(nonatomic, strong) dispatch_queue_t refreshSubscriberQueue;\n','')
        .replace('        _refreshSubscriberCallbacks = [NSMutableDictionary dictionary];\n','')
        .replace('        _refreshSubscriberQueue = dispatch_queue_create("com.tlinkauto.license-subscriber-retirement", DISPATCH_QUEUE_SERIAL);\n','');
    assert.equal(hash(restored),'b8a68a9fc4ac94e6a798bd8046cbeed60271eb58a3b975d6fdfd207227eefb35','complete pre-C06g coordinator/decision/HTTP authority source');
    return restored;
}
export function restoreLifecycleSubscriptionHeader(source){
    const protocol='// Cancels only this subscriber. A delivery already claimed may finish.\n// Shared refresh/HTTP work and other subscribers remain active.\n@protocol SCLicenseRefreshSubscription <NSObject>\n- (void)cancel;\n@end\n\n';
    const method='\n- (id<SCLicenseRefreshSubscription>)subscribeToBackgroundRefreshWithCompletion:(SCLicenseLifecycleCompletion)completion;';
    const restored=source.replace(protocol,'').replace(method,'');
    assert.equal(hash(restored),'29efbafb19caa59914e878ecdbf00b8c046890e2642c54d78be51b1d170e03e7','complete pre-C06g coordinator public API');
    return restored;
}
export function restoreBackgroundSchedulerSubscription(source){
    const addition='                id<SCLicenseRefreshSubscription> subscription =\n                    [self.licenseCoordinator subscribeToBackgroundRefreshWithCompletion:ensureService];\n                if (!subscription) {\n                    run->finish(NO, @"license_refresh_subscription_unavailable", nil);\n                    return;\n                }\n                run->installCleanup(^{ [subscription cancel]; });';
    assert.equal(source.split(addition).length,2);
    const restored=source.replace(addition,'                [self.licenseCoordinator performBackgroundRefreshWithCompletion:ensureService];');
    assert.equal(hash(restored),'b96b40f49b6e29d1e76b247dd574137b085283b49378e3a3d92a73044f7aa551','complete pre-C06g scheduler including owner-queue start permission');
    return restored;
}
export function restoreBackgroundTaskCleanup(source){
    const helper=section(source,'    // Cleanup is best effort;','public:\n');
    const install=section(source,'    // One cleanup is published by the scheduler.','    void arm(int64_t nanoseconds) {');
    const restored=source.replace('    dispatch_block_t cleanup_=nil;\n','').replace(helper,'public:\n').replace(install,'    void arm(int64_t nanoseconds) {')
        .replace('        dispatch_block_t cleanup=nil;\n','').replace('            cleanup=cleanup_; cleanup_=nil;\n','').replace('        invokeCleanup(cleanup);\n','');
    assert.equal(hash(restored),'9ecfcbefdbfbad9d3d8f11f07b67660c5367c8a1c4632a767e6dd0ff62c56408','complete pre-C06g BGTask phases/timer/completion');
    return restored;
}
