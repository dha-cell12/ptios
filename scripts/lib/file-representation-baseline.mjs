import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
export const fileRepresentationSpecs=JSON.parse(readFileSync(new URL('./file-representation-specs.json',import.meta.url),'utf8'));
const frozen=name=>readFileSync(new URL('../../test/fixtures/file-representation-'+name+'-before-c03am.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreFileRepresentationHeader(source){
    if(!source.includes('readTextRequest:'))return source;
    assert.equal(hash(source),fileRepresentationSpecs.header.currentHash,'complete explicit-read header');
    const previous=frozen('header');assert.equal(hash(previous),fileRepresentationSpecs.header.beforeHash);return previous;
}
export function restoreFileRepresentation(source){
    if(!source.includes('// BEGIN selected file reads.'))return source;
    assert.equal(hash(source),fileRepresentationSpecs.implementation.currentHash,'complete explicit-read implementation');
    for(const part of fileRepresentationSpecs.insertions){
        const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a,part.start);
        assert.equal(hash(source.slice(a,b)),part.hash,part.start);source=source.slice(0,a)+source.slice(b);
    }
    for(const part of fileRepresentationSpecs.implementation.parts){
        const a=source.indexOf(part.start),b=source.indexOf(part.end,a+part.start.length);assert.ok(a>=0&&b>a,part.name);
        assert.equal(hash(source.slice(a,b)),part.currentHash,part.name);source=source.slice(0,a)+frozen(part.name)+source.slice(b);
    }
    assert.equal(hash(source),fileRepresentationSpecs.implementation.beforeHash,'complete preceding class and bindings retained');return source;
}
