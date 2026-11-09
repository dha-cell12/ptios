import {restoreProductionLog} from './production-log-baseline.mjs';
import {restoreConsoleRetention} from './console-retention-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
export const storageJSONWriteSpecs=JSON.parse(readFileSync(new URL('./storage-json-write-specs.json',import.meta.url),'utf8'));
export const storageJSONWriteBefore=kind=>readFileSync(new URL('../../test/fixtures/storage-json-write-'+kind+'-before-c03an.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function checkPreparedJSONText(source){
    const before=readFileSync(new URL('../../test/fixtures/prepared-json-before-path-error-fix.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
    assert.equal(hash(before),storageJSONWriteSpecs.adapterHash,'complete preceding prepared JSON adapter');
    const oldWriter='    if (encoding != NSUTF8StringEncoding) return [_decodedJSON writeToFile:path atomically:atomic encoding:encoding error:error];';
    const newWriter="    // Preserve the original string writer's validation before any IO begins.\n    if (encoding != NSUTF8StringEncoding || ![path isKindOfClass:[NSString class]] || path.length == 0)\n        return [_decodedJSON writeToFile:path atomically:atomic encoding:encoding error:error];";
    assert.equal(source.split(newWriter).length-1,1,'one pre-write compatibility selection');
    assert.equal(source.replace(newWriter,oldWriter),before,'only invalid-target writer selection changes; no post-write retry');
}
export function restoreStorageJSONWrites(source,kind){
    if(kind==='helper')source=restoreConsoleRetention(source,'helper');
    if(kind==='troll')source=restoreProductionLog(source);
    const spec=storageJSONWriteSpecs[kind];
    if(!spec||!source.includes(spec.include))return source;
    assert.equal(hash(source),spec.currentHash,'complete prepared JSON '+kind);
    const a=source.indexOf(spec.start),b=source.indexOf(spec.end,a+spec.start.length);assert.ok(a>=0&&b>a);
    assert.equal(hash(source.slice(a,b)),spec.partHash,'complete prepared JSON route '+kind);
    source=(source.slice(0,a)+storageJSONWriteBefore(kind)+source.slice(b)).replace(spec.include,'');
    assert.equal(hash(source),spec.beforeHash,'complete preceding storage/authority source '+kind);return source;
}
