import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreUISnapshot} from './license-ui-snapshot-baseline.mjs';
export const legacyLicensePublish=readFileSync(new URL('../../test/fixtures/license-publish-before-c06v.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
function section(s,a,b){const x=s.indexOf(a),y=s.indexOf(b,x);assert.ok(x>=0&&y>x,a);return s.slice(x,y+b.length);}
export const reloadProperties=s=>section(s,'// BEGIN daemon reload ownership.','// END daemon reload ownership.\n');
export const reloadMethods=s=>section(s,'// BEGIN coalesced daemon reload.','// END coalesced daemon reload.\n\n');
export const licensePublish=s=>{const a=s.indexOf('- (void)publishLicenseChange:'),b=s.indexOf('// BEGIN coalesced daemon reload.',a);assert.ok(a>=0&&b>a);return s.slice(a,b);};
export function restoreReloadCoalescing(source){
    source=restoreUISnapshot(source);
    const current=licensePublish(source),prefix=legacyLicensePublish.slice(0,legacyLicensePublish.indexOf('    dispatch_async(dispatch_get_global_queue'));
    assert.equal(current,prefix+'    [self requestDaemonReload];\n}\n\n','complete per-publication invalidation/UI/generation/diagnostics/notification source');
    const restored=source.replace(reloadProperties(source),'').replace(reloadMethods(source),'').replace(current,legacyLicensePublish)
        .replace('        _daemonReloadQueue = dispatch_queue_create("com.tlinkauto.license-daemon-reload", DISPATCH_QUEUE_SERIAL);\n','');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'ac101d3c72c97dd71349c7641ffa6f413425fc2a08d8474cc98a4ee91b3d68aa',
        'complete prior coordinator HTTP/authority/activation/subscription/UI/diagnostics/transport source');
    return restored;
}
