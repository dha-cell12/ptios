import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const productionLogBatchSpecs=JSON.parse(readFileSync(new URL('./production-log-batch-specs.json',import.meta.url),'utf8'));
export const productionLogBatchBefore=readFileSync(new URL('../../test/fixtures/production-log-backend-before-c03aw.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreProductionLogBackend(source){
    if(!source.includes('TLinkProductionLogBatch.h'))return source;
    assert.equal(hash(source),productionLogBatchSpecs.currentHash,'complete production batch backend');
    assert.equal(hash(productionLogBatchBefore),productionLogBatchSpecs.beforeHash,'complete preceding admitted per-record backend');
    assert.equal(hash(readFileSync(new URL('../../shared/TLinkProductionLogBatch.h',import.meta.url),'utf8').replaceAll('\r\n','\n')),productionLogBatchSpecs.coreHash,'complete grouping/weak-registration policy');
    return productionLogBatchBefore;
}
