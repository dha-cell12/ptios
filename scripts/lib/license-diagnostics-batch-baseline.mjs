import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const diagnosticsBatchBefore=readFileSync(new URL('../../test/fixtures/license-diagnostics-batch-before-c06ae.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export const diagnosticsBatchSpecs=JSON.parse(readFileSync(new URL('./license-diagnostics-batch-specs.json',import.meta.url),'utf8'));
export function restoreDiagnosticsBatch(source){
    if(!source.includes('// BEGIN synchronous diagnostics batch.'))return source;
    assert.equal(hash(source),diagnosticsBatchSpecs.currentHash,'complete synchronous diagnostics batch coordinator');
    for(const part of [...diagnosticsBatchSpecs.parts].reverse()){
        assert.equal(source.split(part.current).length,2,'one complete diagnostics '+part.name);
        source=source.replace(part.current,part.before);
    }
    assert.equal(source,diagnosticsBatchBefore,'complete preceding coordinator/manager/authority/reload/UI source');
    assert.equal(hash(source),diagnosticsBatchSpecs.beforeHash);return source;
}
