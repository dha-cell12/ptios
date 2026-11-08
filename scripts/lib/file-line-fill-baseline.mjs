import {restoreFileReadStorage} from './file-read-storage-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=text=>createHash('sha256').update(text).digest('hex');
export const fileLineFillSpecs=JSON.parse(readFileSync(new URL('./file-line-fill-specs.json',import.meta.url),'utf8'));
export function checkFileLineFillCore(source){assert.equal(hash(source),fileLineFillSpecs.coreHash,'complete direct line destination core');}
export function restoreFileLineFill(source){
    source=restoreFileReadStorage(source);
    const spec=fileLineFillSpecs;
    if(!source.includes(spec.include))return source;
    assert.equal(hash(source),spec.currentHash,'complete direct line implementation');
    source=source.replace(spec.include,'');
    const a=source.indexOf(spec.formatterStart),b=source.indexOf(spec.formatterEnd,a+spec.formatterStart.length);assert.ok(a>=0&&b>a);
    assert.equal(hash(source.slice(a,b)),spec.formatterHash,'complete direct mutable line result');source=source.slice(0,a)+source.slice(b);
    const start=source.indexOf(spec.start,source.indexOf('- (NSDictionary *)readLine\n')),end=source.indexOf(spec.end,start+spec.start.length);assert.ok(start>=0&&end>start);
    assert.equal(hash(source.slice(start,end)),spec.partHash,'complete direct line reader');
    const before=readFileSync(new URL('../../test/fixtures/file-line-fill-read-before-c03ao.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
    source=source.slice(0,start)+before+source.slice(end);
    assert.equal(hash(source),spec.beforeHash,'complete preceding shared FileHandle retained');return source;
}
