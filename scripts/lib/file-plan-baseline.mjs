import {restoreFileRepresentation,restoreFileRepresentationHeader} from './file-representation-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const filePlanSpecs=JSON.parse(readFileSync(new URL('./file-plan-specs.json',import.meta.url),'utf8'));
const frozen=name=>readFileSync(new URL('../../test/fixtures/file-plan-'+name+'-before-c03al.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreFilePlanHeader(source){source=restoreFileRepresentationHeader(source);assert.equal(hash(source),filePlanSpecs.header.currentHash);return frozen('header');}
export function checkFileModePlan(source){assert.equal(hash(source),filePlanSpecs.planHash,'complete immutable mode plan');}
export function restoreFilePlan(source){
    source=restoreFileRepresentation(source);
    if(!source.includes('// BEGIN prepared file mode.'))return source;
    assert.equal(hash(source),filePlanSpecs.implementation.currentHash,'complete C03al FileHandle');
    for(const [a,b] of [['// BEGIN prepared file mode.','static NSDictionary *TLinkJSFileError('],['// BEGIN prepared physical open declaration.','@property(nonatomic, readwrite) NSUInteger handleId;']]){
        const start=source.indexOf(a),end=source.indexOf(b,start);assert.ok(start>=0&&end>start);source=source.slice(0,start)+source.slice(end);
    }
    for(const part of filePlanSpecs.implementation.parts){
        const a=source.indexOf(part.start),b=part.end?source.indexOf(part.end,a+part.start.length):source.length;assert.ok(a>=0&&b>a);
        assert.equal(hash(source.slice(a,b)),part.currentHash,part.name);source=source.slice(0,a)+frozen(part.name)+source.slice(b);
    }
    assert.equal(hash(source),filePlanSpecs.implementation.beforeHash,'complete C03ag class retained');return source;
}
export function restoreFilePlanFrontend(source,kind,complete=false){
    const spec=filePlanSpecs[kind];
    if(!source.includes('TLinkJSFilePrepareMode(openMode)'))return source;
    if(complete)assert.equal(hash(source),spec.currentHash,'complete prepared '+kind);
    const a=source.indexOf(spec.start),b=source.indexOf(spec.end,a+spec.start.length);assert.ok(a>=0&&b>a);
    assert.equal(hash(source.slice(a,b)),spec.partHash,'prepared frontend '+kind);
    source=source.slice(0,a)+frozen(kind)+source.slice(b);
    if(complete)assert.equal(hash(source),spec.beforeHash,'complete preceding '+kind);return source;
}
