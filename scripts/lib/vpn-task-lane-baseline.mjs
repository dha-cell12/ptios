import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
export async function beforeVPNTaskLane(source){
    const start=source.indexOf('// BEGIN VPN task owner queue.');
    const end=source.indexOf('static void zx_deferTask(',start);
    assert.ok(start>=0&&end>start);
    const queue=source.slice(start,end);
    const before=source.replace('#include "../shared/TLinkVPNTaskAdmission.h"\n','')
        .replace('static size_t gPendingVPNTasks = 0;\n','').replace(queue,'')
        .replace('    const bool vpnTask=TLinkVPNTaskPayload(task,taskLength);\n','')
        .replace('TLinkVPNTaskLaneAvailable(vpnTask,imageTask,gPendingTasks,gPendingImageTasks,gPendingVPNTasks)','TLinkC01LaneAvailable(imageTask,gPendingTasks,gPendingImageTasks)')
        .replace('// Rejected work never enters an owner queue.','// Rejected work never enters either owner queue.')
        .replace('    if(imageTask||vpnTask){','    if(imageTask){')
        .replace('requestBudget=vpnTask?TLinkVPNIPCBudget(parent):TLinkC01TaskBudget(task,taskLength,parent);','requestBudget=TLinkC01TaskBudget(task,taskLength,parent);')
        .replace('    if(vpnTask)++gPendingVPNTasks;\n','')
        .replace('workQueue=vpnTask?zx_vpnTaskQueue():(imageTask?zx_imageTaskQueue():zx_taskQueue());','workQueue=imageTask?zx_imageTaskQueue():zx_taskQueue();')
        .replace('                        const char *expired=vpnTask?"1;;vpn_request_expired\\r\\n":"1;;c01_request_expired\\r\\n";\n                        legacy=TLinkNativeStopped()?zx_dataFromCString(expired):zx_handleLegacyRequestBytes([payload UTF8String]);\n                        if(TLinkNativeStopped())legacy=zx_dataFromCString(expired);',
            '                        legacy=TLinkNativeStopped()?zx_dataFromCString("1;;c01_request_expired\\r\\n"):zx_handleLegacyRequestBytes([payload UTF8String]);\n                        if(TLinkNativeStopped())legacy=zx_dataFromCString("1;;c01_request_expired\\r\\n");')
        .replace('                if(vpnTask)--gPendingVPNTasks;\n','');
    const frozen=(await readFile(new URL('../../test/fixtures/vpn-task-lane-before-c04i.inc',import.meta.url),'utf8')).replaceAll('\r\n','\n');
    assert.equal(createHash('sha256').update(frozen).digest('hex'),'bcfa821cf065dd85104fe4bd5eaccd3a59bcccda9dbb3e0847268dbd6c7b30f3');
    assert.equal(before,frozen,'only bounded VPN task lane/budget/admission changes complete C04h daemon source');
    return before;
}
